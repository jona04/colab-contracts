// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "../interfaces/IConcentratedLiquidityAdapter.sol";
import {ISwapRouterV3Pancake} from "../interfaces/ISwapRouterV3Pancake.sol";

/**
 * @title ClientVault
 * @notice Single-user, non-upgradeable vault for funds/DAOs following a Colab strategy.
 * @dev
 * - The vault holds the assets (token0, token1) directly.
 * - Concentrated liquidity logic (mint, rebalance, exit, collect, stake) is delegated
 *   to an external IConcentratedLiquidityAdapter implementation.
 * - An off-chain executor address (controlled by Colab) is allowed to trigger
 *   automated rebalances within strict bounds configured by the owner.
 * - No generic "transfer out" functions exist; funds can only flow to:
 *     * the adapter (for LP),
 *     * the fixed dexRouter (for swaps),
 *     * the owner (on exit/withdraw),
 *     * a dedicated feeCollector (future performance fee hook).
 */
contract ClientVault is ReentrancyGuard {
    using SafeERC20 for IERC20;

    // -------------------------------------------------------------------------
    // Immutable configuration
    // -------------------------------------------------------------------------

    /// @notice Owner of this vault (fund/DAO/multisig).
    address public immutable owner;

    /// @notice Off-chain automation executor (Colab bot).
    address public immutable executor;

    /// @notice Concentrated liquidity adapter (Pancake, Uniswap, Aerodrome, etc.).
    IConcentratedLiquidityAdapter public immutable adapter;

    /// @notice Fixed DEX router used for swaps (no arbitrary routers allowed).
    address public immutable dexRouter;

    /// @notice Address that will receive protocol performance fees (future hook).
    address public immutable feeCollector;

    /// @notice Strategy identifier in the StrategyRegistry (off-chain/introspection).
    uint256 public immutable strategyId;

    // -------------------------------------------------------------------------
    // Automation configuration (mutable, controlled by owner)
    // -------------------------------------------------------------------------

    /// @notice Whether automation is enabled for this vault.
    bool public automationEnabled;

    /// @notice Minimum time (in seconds) between automated rebalances.
    uint32 public cooldownSec;

    /// @notice Maximum allowed slippage in basis points (informational / future on-chain checks).
    uint16 public maxSlippageBps;

    /// @notice Whether automated logic is allowed to execute swaps.
    bool public allowSwap;

    // -------------------------------------------------------------------------
    // State
    // -------------------------------------------------------------------------

    /// @notice Last tokenId held by this vault in the adapter.
    uint256 public positionTokenId;

    /// @notice Timestamp of the last successful automated rebalance.
    uint256 public lastRebalanceTs;

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    /// @notice Emitted when the vault is created.
    event VaultInitialized(
        address indexed owner,
        address indexed executor,
        address indexed adapter,
        address dexRouter,
        address feeCollector,
        uint256 strategyId
    );

    /// @notice Emitted when automation is toggled by the owner.
    event AutomationToggled(bool enabled);

    /// @notice Emitted when automation config is updated by the owner.
    event AutomationConfigUpdated(
        uint32 cooldownSec,
        uint16 maxSlippageBps,
        bool allowSwap
    );

    /// @notice Emitted when a new position is opened.
    event PositionOpened(
        uint256 tokenId,
        int24 lower,
        int24 upper,
        uint128 liquidity
    );

    /// @notice Emitted when a manual rebalanceWithCaps is executed by the owner.
    event ManualRebalanced(int24 lower, int24 upper, uint128 newLiquidity);

    /// @notice Emitted when an automated rebalance is executed by the executor.
    event AutoRebalanced(
        int24 lower,
        int24 upper,
        uint128 newLiquidity,
        uint256 swapAmountIn,
        uint256 swapAmountOut
    );

    /// @notice Emitted when the position is exited (but funds remain in the vault).
    event ExitedToVault();

    /// @notice Emitted when the position is exited and all funds are withdrawn to the owner.
    event ExitedAndWithdrawn(
        address indexed to,
        uint256 amount0,
        uint256 amount1
    );

    /// @notice Emitted when fees are collected from the adapter into the vault.
    event Collected(uint256 amount0, uint256 amount1);

    /// @notice Emitted when the position is staked in the underlying gauge/farm.
    event Staked();

    /// @notice Emitted when the position is unstaked from the underlying gauge/farm.
    event Unstaked();

    /// @notice Emitted when a swap via the fixed dexRouter is executed.
    event Swapped(
        address indexed router,
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut
    );

    // -------------------------------------------------------------------------
    // Modifiers
    // -------------------------------------------------------------------------

    modifier onlyOwner() {
        require(msg.sender == owner, "ClientVault: not owner");
        _;
    }

    modifier onlyExecutor() {
        require(msg.sender == executor, "ClientVault: not executor");
        _;
    }

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    /**
     * @notice Constructs a new ClientVault instance.
     * @param _owner Address that owns this vault (fund/DAO/multisig).
     * @param _executor Off-chain automation executor (Colab bot).
     * @param _adapter Concentrated liquidity adapter already wired to a pool.
     * @param _dexRouter Fixed DEX router used for swaps.
     * @param _feeCollector Protocol fee collector (future performance fee hook).
     * @param _strategyId Strategy identifier in the StrategyRegistry.
     * @param _cooldownSec Initial automation cooldown in seconds.
     * @param _maxSlippageBps Initial max slippage in basis points.
     * @param _allowSwap Whether automation is allowed to execute swaps.
     */
    constructor(
        address _owner,
        address _executor,
        address _adapter,
        address _dexRouter,
        address _feeCollector,
        uint256 _strategyId,
        uint32 _cooldownSec,
        uint16 _maxSlippageBps,
        bool _allowSwap
    ) {
        require(_owner != address(0), "ClientVault: owner=0");
        require(_executor != address(0), "ClientVault: executor=0");
        require(_adapter != address(0), "ClientVault: adapter=0");
        require(_dexRouter != address(0), "ClientVault: dexRouter=0");
        // feeCollector MAY be zero in early phases if fees are disabled, but we keep it explicit.

        owner = _owner;
        executor = _executor;
        adapter = IConcentratedLiquidityAdapter(_adapter);
        dexRouter = _dexRouter;
        feeCollector = _feeCollector;
        strategyId = _strategyId;

        automationEnabled = false; // owner must explicitly opt-in
        cooldownSec = _cooldownSec;
        maxSlippageBps = _maxSlippageBps;
        allowSwap = _allowSwap;

        emit VaultInitialized(
            _owner,
            _executor,
            _adapter,
            _dexRouter,
            _feeCollector,
            _strategyId
        );
    }

    // -------------------------------------------------------------------------
    // Views
    // -------------------------------------------------------------------------

    /**
     * @notice Returns the pool tokens for this vault's adapter.
     * @return token0 Address of token0.
     * @return token1 Address of token1.
     */
    function tokens() public view returns (address token0, address token1) {
        return adapter.tokens();
    }

    /**
     * @notice Returns the current vault configuration for automation.
     * @return enabled Whether automation is enabled.
     * @return cooldown Cooldown in seconds between automated rebalances.
     * @return slippageBps Maximum slippage in basis points.
     * @return swapAllowed Whether automation is allowed to execute swaps.
     */
    function getAutomationConfig()
        external
        view
        returns (
            bool enabled,
            uint32 cooldown,
            uint16 slippageBps,
            bool swapAllowed
        )
    {
        return (automationEnabled, cooldownSec, maxSlippageBps, allowSwap);
    }

    /**
     * @notice Minimal positionId view for off-chain bots/APIs.
     * @return tokenId Current tokenId held by this vault in the adapter.
     */
    function positionTokenIdView() external view returns (uint256 tokenId) {
        return positionTokenId;
    }

    // -------------------------------------------------------------------------
    // Owner-configurable automation
    // -------------------------------------------------------------------------

    /**
     * @notice Enable or disable automation for this vault.
     * @param enabled True to enable, false to disable.
     */
    function setAutomationEnabled(bool enabled) external onlyOwner {
        automationEnabled = enabled;
        emit AutomationToggled(enabled);
    }

    /**
     * @notice Update automation configuration limits.
     * @dev These values are used by the off-chain executor as hard bounds
     *      and can also be enforced on-chain in future iterations (e.g., with quotes).
     * @param _cooldownSec Minimum time between automated rebalances.
     * @param _maxSlippageBps Maximum slippage allowed in basis points.
     * @param _allowSwap Whether automation is allowed to perform swaps.
     */
    function setAutomationConfig(
        uint32 _cooldownSec,
        uint16 _maxSlippageBps,
        bool _allowSwap
    ) external onlyOwner {
        cooldownSec = _cooldownSec;
        maxSlippageBps = _maxSlippageBps;
        allowSwap = _allowSwap;

        emit AutomationConfigUpdated(_cooldownSec, _maxSlippageBps, _allowSwap);
    }

    // -------------------------------------------------------------------------
    // Internal helpers
    // -------------------------------------------------------------------------

    /**
     * @dev Approves `spender` to spend `needed` of `token` from this vault if current allowance is insufficient.
     */
    function _approveIfNeeded(
        address token,
        address spender,
        uint256 needed
    ) internal {
        if (needed == 0) return;
        uint256 allowance_ = IERC20(token).allowance(address(this), spender);
        if (allowance_ < needed) {
            IERC20(token).forceApprove(spender, 0);
            IERC20(token).forceApprove(spender, type(uint256).max);
        }
    }

    /**
     * @dev Opens a new position using all idle balances of token0/token1 currently held by this vault.
     *      Reverts if no funds are present.
     * @param lower Lower tick of the new position.
     * @param upper Upper tick of the new position.
     * @return tid Newly created position tokenId.
     * @return L   Liquidity of the new position.
     */
    function _openWithAllIdle(
        int24 lower,
        int24 upper
    ) internal returns (uint256 tid, uint128 L) {
        (address token0, address token1) = adapter.tokens();

        uint256 bal0 = IERC20(token0).balanceOf(address(this));
        uint256 bal1 = IERC20(token1).balanceOf(address(this));
        require(bal0 > 0 || bal1 > 0, "ClientVault: no funds");

        // Approve adapter to pull current balances
        _approveIfNeeded(token0, address(adapter), bal0);
        _approveIfNeeded(token1, address(adapter), bal1);

        (tid, L) = adapter.openInitialPosition(address(this), lower, upper);
        positionTokenId = tid;

        emit PositionOpened(tid, lower, upper, L);
    }

    /**
     * @dev Internal swap helper using the fixed dexRouter and Pancake V3 interface.
     * @param tokenIn Input token (must be token0 or token1 of the pool).
     * @param tokenOut Output token (must be the complementary pool token).
     * @param fee Pool fee tier.
     * @param amountIn Exact input amount (raw units).
     * @param amountOutMinimum Minimum acceptable output (raw units) for slippage protection.
     * @param sqrtPriceLimitX96 Optional price limit (usually 0).
     * @return amountOut Amount of tokenOut received.
     */
    function _swapExactInPancake(
        address tokenIn,
        address tokenOut,
        uint24 fee,
        uint256 amountIn,
        uint256 amountOutMinimum,
        uint160 sqrtPriceLimitX96
    ) internal returns (uint256 amountOut) {
        require(dexRouter != address(0), "ClientVault: router=0");
        require(amountIn > 0, "ClientVault: amountIn=0");

        _approveIfNeeded(tokenIn, dexRouter, amountIn);

        ISwapRouterV3Pancake.ExactInputSingleParams
            memory p = ISwapRouterV3Pancake.ExactInputSingleParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                fee: fee,
                recipient: address(this),
                deadline: block.timestamp + 900,
                amountIn: amountIn,
                amountOutMinimum: amountOutMinimum,
                sqrtPriceLimitX96: sqrtPriceLimitX96
            });

        amountOut = ISwapRouterV3Pancake(dexRouter).exactInputSingle{value: 0}(
            p
        );

        // Defensive: reset approval
        IERC20(tokenIn).forceApprove(dexRouter, 0);

        emit Swapped(dexRouter, tokenIn, tokenOut, amountIn, amountOut);
    }

    // -------------------------------------------------------------------------
    // Manual owner actions
    // -------------------------------------------------------------------------

    /**
     * @notice Swap manual via Pancake V3 usando o router fixo do vault.
     * @dev
     * - Apenas o owner pode chamar.
     * - Usa sempre o `dexRouter` imutável.
     * - Mantém os fundos dentro do vault (recipient = address(this)).
     * - Útil para conversão pontual (ex.: rewards -> USDC para
     *   contabilizar em convert_gauge_to_usdc no backend).
     *
     * @param tokenIn  Token de entrada.
     * @param tokenOut Token de saída.
     * @param fee      Fee tier da pool.
     * @param amountIn Quantidade exata de entrada (raw).
     * @param amountOutMinimum Mínimo aceitável de saída (slippage).
     * @param sqrtPriceLimitX96 Limite opcional de preço (0 = sem limite).
     * @return amountOut Quantidade recebida de tokenOut.
     */
    function swapExactInPancake(
        address tokenIn,
        address tokenOut,
        uint24 fee,
        uint256 amountIn,
        uint256 amountOutMinimum,
        uint160 sqrtPriceLimitX96
    ) external onlyOwner nonReentrant returns (uint256 amountOut) {
        amountOut = _swapExactInPancake(
            tokenIn,
            tokenOut,
            fee,
            amountIn,
            amountOutMinimum,
            sqrtPriceLimitX96
        );
    }

    /**
     * @notice Open the initial position using all idle balances in the vault.
     * @dev Only callable by the owner. Will revert if no funds.
     * @param lower Lower tick of the position.
     * @param upper Upper tick of the position.
     */
    function openInitialPosition(
        int24 lower,
        int24 upper
    ) external onlyOwner nonReentrant {
        (uint256 tid, uint128 L) = _openWithAllIdle(lower, upper);
        // Optionally stake immediately if adapter supports it
        try adapter.stakePosition(address(this)) {
            emit Staked();
        } catch {}
        // PositionOpened already emitted inside _openWithAllIdle
        // L is emitted; we just avoid unused warning:
        L;
        tid;
    }

    /**
     * @notice Manual rebalance using caps (advanced owner operation).
     * @dev Semantics similar to SingleUserVaultV2.rebalanceWithCaps.
     * @param lower New lower tick.
     * @param upper New upper tick.
     * @param cap0 Maximum amount of token0 to use (0 = use all available).
     * @param cap1 Maximum amount of token1 to use (0 = use all available).
     */
    function rebalanceWithCaps(
        int24 lower,
        int24 upper,
        uint256 cap0,
        uint256 cap1
    ) external onlyOwner nonReentrant {
        // Note: adapter handles cooldowns and internal validations if configured.
        uint128 L = adapter.rebalanceWithCaps(
            address(this),
            lower,
            upper,
            cap0,
            cap1
        );
        positionTokenId = adapter.currentTokenId(address(this));
        emit ManualRebalanced(lower, upper, L);
    }

    /**
     * @notice Exit the position, keeping resulting tokens in the vault.
     * @dev Only callable by the owner.
     */
    function exitPositionToVault() external onlyOwner nonReentrant {
        adapter.exitPositionToVault(address(this));
        positionTokenId = adapter.currentTokenId(address(this)); // likely 0
        emit ExitedToVault();
    }

    /**
     * @notice Exit the position and withdraw all vault balances to `to`.
     * @dev
     * - Closes the position (if any) via the adapter.
     * - Transfers all token0 and token1 balances held by this vault to `to`.
     * - Future performance-fee logic can be added here before sending funds out.
     * @param to Recipient address (must not be zero).
     */
    function exitPositionAndWithdrawAll(
        address to
    ) external onlyOwner nonReentrant {
        require(to != address(0), "ClientVault: to=0");

        // 1) Exit position (collect + remove liquidity)
        adapter.exitPositionToVault(address(this));
        positionTokenId = adapter.currentTokenId(address(this)); // expected 0

        // 2) Transfer all balances to `to`
        (address token0, address token1) = adapter.tokens();

        uint256 b0 = IERC20(token0).balanceOf(address(this));
        uint256 b1 = IERC20(token1).balanceOf(address(this));

        if (b0 > 0) {
            IERC20(token0).safeTransfer(to, b0);
        }
        if (b1 > 0) {
            IERC20(token1).safeTransfer(to, b1);
        }

        emit ExitedAndWithdrawn(to, b0, b1);
    }

    /**
     * @notice Collect fees from the adapter into the vault.
     * @dev Only owner can trigger; fees remain in the vault as idle balances.
     * @return amount0 Amount of token0 collected.
     * @return amount1 Amount of token1 collected.
     */
    function collectToVault()
        external
        onlyOwner
        nonReentrant
        returns (uint256 amount0, uint256 amount1)
    {
        (amount0, amount1) = adapter.collectToVault(address(this));
        emit Collected(amount0, amount1);
    }

    /**
     * @notice Stake the current position in the underlying gauge/farm (if any).
     */
    function stake() external onlyOwner nonReentrant {
        adapter.stakePosition(address(this));
        emit Staked();
    }

    /**
     * @notice Unstake the current position from the underlying gauge/farm (if any).
     */
    function unstake() external onlyOwner nonReentrant {
        adapter.unstakePosition(address(this));
        emit Unstaked();
    }

    /**
     * @notice Claim rewards from the underlying gauge/farm.
     * @dev Adapter should be implemented to send rewards directly to this vault.
     */
    function claimRewards() external onlyOwner nonReentrant {
        adapter.claimRewards(address(this));
    }

    // -------------------------------------------------------------------------
    // Automated executor actions
    // -------------------------------------------------------------------------

    /**
     * @notice Parameters for automated rebalance on a Pancake-like CL DEX.
     * @dev
     * - All values are usually computed off-chain by the strategy engine.
     * - tokenIn/tokenOut must match the pool tokens returned by adapter.tokens().
     */
    struct AutoRebalanceParams {
        int24 newLower;
        int24 newUpper;
        uint24 fee;
        address tokenIn;
        address tokenOut;
        uint256 swapAmountIn; // 0 = no swap
        uint256 swapAmountOutMin; // quoted minOut, respecting maxSlippageBps off-chain
        uint160 sqrtPriceLimitX96; // optional, usually 0
    }

    /**
     * @notice Automated rebalance entry point for Pancake V3-style pools.
     * @dev
     * Flow:
     *  1) (best-effort) unstake in adapter.gauge, if any.
     *  2) exitPositionToVault -> funds return to this vault.
     *  3) optional swap via fixed dexRouter (if swapAmountIn > 0).
     *  4) reopen position using all idle balances in [newLower, newUpper].
     *  5) (best-effort) restake position via adapter.
     *
     * Security:
     *  - Only the pre-defined `executor` may call this function.
     *  - Automation must be enabled by the owner.
     *  - cooldwonSec is enforced against lastRebalanceTs.
     *  - tokenIn/tokenOut must be the pool tokens (adapter.tokens()).
     *  - If allowSwap == false, swapAmountIn must be 0.
     *
     * @param params Struct containing rebalance parameters computed off-chain.
     */
    function autoRebalancePancake(
        AutoRebalanceParams calldata params
    ) external onlyExecutor nonReentrant {
        require(automationEnabled, "ClientVault: automation disabled");

        if (cooldownSec > 0) {
            require(
                block.timestamp >= lastRebalanceTs + cooldownSec,
                "ClientVault: cooldown"
            );
        }

        // Basic tick sanity (does not enforce spacing; adapter/pool will revert if invalid)
        require(
            params.newLower < params.newUpper,
            "ClientVault: invalid range"
        );

        (address token0, address token1) = adapter.tokens();
        require(
            (params.tokenIn == token0 && params.tokenOut == token1) ||
                (params.tokenIn == token1 && params.tokenOut == token0),
            "ClientVault: tokens mismatch"
        );

        if (!allowSwap) {
            require(params.swapAmountIn == 0, "ClientVault: swap disabled");
        }

        // ---------------------------------------------------------------------
        // 1) Best-effort unstake
        // ---------------------------------------------------------------------
        try adapter.unstakePosition(address(this)) {
            emit Unstaked();
        } catch {
            // ignore if no gauge or already unstaked
        }

        // ---------------------------------------------------------------------
        // 2) Exit current position -> funds back to vault
        // ---------------------------------------------------------------------
        adapter.exitPositionToVault(address(this));
        positionTokenId = adapter.currentTokenId(address(this)); // expected 0
        emit ExitedToVault();

        // ---------------------------------------------------------------------
        // 3) Optional swap via fixed dexRouter
        // ---------------------------------------------------------------------
        uint256 amountOutSwap = 0;
        if (params.swapAmountIn > 0) {
            amountOutSwap = _swapExactInPancake(
                params.tokenIn,
                params.tokenOut,
                params.fee,
                params.swapAmountIn,
                params.swapAmountOutMin,
                params.sqrtPriceLimitX96
            );
        }

        // ---------------------------------------------------------------------
        // 4) Open new position with all idle balances
        // ---------------------------------------------------------------------
        (uint256 tid, uint128 L) = _openWithAllIdle(
            params.newLower,
            params.newUpper
        );

        // ---------------------------------------------------------------------
        // 5) Best-effort restake
        // ---------------------------------------------------------------------
        try adapter.stakePosition(address(this)) {
            emit Staked();
        } catch {
            // ignore if no gauge or staking reverted
        }

        lastRebalanceTs = block.timestamp;

        emit AutoRebalanced(
            params.newLower,
            params.newUpper,
            L,
            params.swapAmountIn,
            amountOutSwap
        );

        // avoid unused warnings
        tid;
    }
}
