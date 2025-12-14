// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC721Receiver} from "openzeppelin-contracts/contracts/token/ERC721/IERC721Receiver.sol";
import {IERC721} from "openzeppelin-contracts/contracts/token/ERC721/IERC721.sol";

import "../../interfaces/IConcentratedLiquidityAdapter.sol";
import "./interfaces/IPancakeV3PoolMinimal.sol";
import "./interfaces/IPancakeV3NFPM.sol";
import "./interfaces/IMasterChefV3.sol";

/**
 * @title PancakeV3Adapter
 * @notice PancakeSwap v3 (CLAMM) adapter with optional staking in MasterChefV3.
 * @dev
 * - Implements the IConcentratedLiquidityAdapter interface.
 * - Keeps one LP NFT per vault, stored in this adapter contract.
 * - LP lifecycle:
 *     * openInitialPosition: pulls tokens from the vault, mints an NFT, returns leftovers.
 *     * rebalanceWithCaps: collects fees, closes the old position, optionally pulls more tokens,
 *                          mints a new NFT in the requested range, returns leftovers.
 *     * exitPositionToVault: closes the position and returns all tokens to the vault.
 *     * collectToVault: collects fees and forwards them to the vault.
 * - Optional staking:
 *     * stakePosition / unstakePosition / claimRewards via MasterChefV3.
 * - All risk / automation logic (cooldown, slippage, ranges, etc.) is handled by ClientVault
 *   or off-chain, not by this adapter.
 */
contract PancakeV3Adapter is IConcentratedLiquidityAdapter, IERC721Receiver {
    using SafeERC20 for IERC20;

    // -------------------------------------------------------------------------
    // Immutable protocol wiring
    // -------------------------------------------------------------------------

    /// @inheritdoc IConcentratedLiquidityAdapter
    address public immutable override pool;

    /// @inheritdoc IConcentratedLiquidityAdapter
    address public immutable override nfpm;

    /// @inheritdoc IConcentratedLiquidityAdapter
    address public immutable override gauge; // MasterChefV3 (can be zero)

    // -------------------------------------------------------------------------
    // Position tracking
    // -------------------------------------------------------------------------

    /// @notice Current LP NFT id per vault.
    mapping(address => uint256) private _tokenId;

    /// @notice Timestamp of the last rebalance performed for each vault (for analytics).
    mapping(address => uint256) public lastRebalance;

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    /**
     * @notice Construct a new PancakeV3Adapter.
     * @param _pool Address of the Pancake v3 pool.
     * @param _nfpm Address of the Pancake v3 Non-Fungible Position Manager.
     * @param _masterChefV3 Address of the MasterChefV3 gauge (can be zero if no staking).
     */
    constructor(address _pool, address _nfpm, address _masterChefV3) {
        require(
            _pool != address(0) && _nfpm != address(0),
            "PancakeV3Adapter: zero address"
        );
        pool = _pool;
        nfpm = _nfpm;
        gauge = _masterChefV3; // may be zero to disable staking
    }

    // -------------------------------------------------------------------------
    // ERC721 Receiver
    // -------------------------------------------------------------------------

    /**
     * @inheritdoc IERC721Receiver
     */
    function onERC721Received(
        address /* operator */,
        address /* from */,
        uint256 /* id */,
        bytes calldata /* data */
    ) external pure override returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    // -------------------------------------------------------------------------
    // Basic views
    // -------------------------------------------------------------------------

    /**
     * @inheritdoc IConcentratedLiquidityAdapter
     */
    function tokens()
        public
        view
        override
        returns (address token0, address token1)
    {
        token0 = IPancakeV3PoolMinimal(pool).token0();
        token1 = IPancakeV3PoolMinimal(pool).token1();
    }

    /**
     * @inheritdoc IConcentratedLiquidityAdapter
     */
    function tickSpacing() external view override returns (int24) {
        return IPancakeV3PoolMinimal(pool).tickSpacing();
    }

    /**
     * @inheritdoc IConcentratedLiquidityAdapter
     */
    function slot0()
        external
        view
        override
        returns (uint160 sqrtPriceX96, int24 tick)
    {
        (sqrtPriceX96, tick, , , , , ) = IPancakeV3PoolMinimal(pool).slot0();
    }

    /**
     * @inheritdoc IConcentratedLiquidityAdapter
     */
    function currentTokenId(
        address vault
    ) public view override returns (uint256) {
        return _tokenId[vault];
    }

    /**
     * @notice Returns the current range and liquidity for a vault's position.
     * @param vault Vault address.
     * @return lower Current lower tick.
     * @return upper Current upper tick.
     * @return liquidity Current liquidity.
     */
    function currentRange(
        address vault
    ) external view returns (int24 lower, int24 upper, uint128 liquidity) {
        uint256 tid = _tokenId[vault];
        require(tid != 0, "PancakeV3Adapter: no position");
        (, , , , , int24 l, int24 u, uint128 L, , , , ) = IPancakeV3NFPM(nfpm)
            .positions(tid);
        return (l, u, L);
    }

    // -------------------------------------------------------------------------
    // Internal helpers
    // -------------------------------------------------------------------------

    /**
     * @dev Approve `spender` to spend `amount` of `token` if current allowance is lower.
     *      Uses SafeERC20.forceApprove pattern.
     */
    function _approveIfNeeded(
        address token,
        address spender,
        uint256 amount
    ) internal {
        if (amount == 0) return;
        uint256 allowance = IERC20(token).allowance(address(this), spender);
        if (allowance < amount) {
            IERC20(token).forceApprove(spender, 0);
            IERC20(token).forceApprove(spender, type(uint256).max);
        }
    }

    /**
     * @dev Returns true if the given tokenId is currently staked in the gauge.
     * @param tokenId LP NFT id.
     */
    function _isStaked(uint256 tokenId) internal view returns (bool) {
        if (tokenId == 0) return false;
        try IERC721(nfpm).ownerOf(tokenId) returns (address owner_) {
            return owner_ != address(this);
        } catch {
            return false;
        }
    }

    // -------------------------------------------------------------------------
    // MAIN LP LOGIC
    // -------------------------------------------------------------------------

    /**
     * @inheritdoc IConcentratedLiquidityAdapter
     */
    function openInitialPosition(
        address vault,
        int24 tickLower,
        int24 tickUpper
    ) external override returns (uint256 tokenId, uint128 liquidity) {
        require(_tokenId[vault] == 0, "PancakeV3Adapter: already opened");

        (address token0, address token1) = tokens();
        uint256 a0 = IERC20(token0).balanceOf(vault);
        uint256 a1 = IERC20(token1).balanceOf(vault);
        require(a0 > 0 || a1 > 0, "PancakeV3Adapter: no funds");

        // 1) Pull tokens from vault into the adapter
        if (a0 > 0) IERC20(token0).safeTransferFrom(vault, address(this), a0);
        if (a1 > 0) IERC20(token1).safeTransferFrom(vault, address(this), a1);

        // 2) Approve NFPM to spend tokens
        _approveIfNeeded(token0, nfpm, a0);
        _approveIfNeeded(token1, nfpm, a1);

        // 3) Mint the LP NFT
        uint24 fee = IPancakeV3PoolMinimal(pool).fee();

        IPancakeV3NFPM.MintParams memory p = IPancakeV3NFPM.MintParams({
            token0: token0,
            token1: token1,
            fee: fee,
            tickLower: tickLower,
            tickUpper: tickUpper,
            amount0Desired: a0,
            amount1Desired: a1,
            amount0Min: 0,
            amount1Min: 0,
            recipient: address(this),
            deadline: block.timestamp + 900
        });

        (tokenId, liquidity, , ) = IPancakeV3NFPM(nfpm).mint(p);
        _tokenId[vault] = tokenId;

        // 4) Return leftovers back to the vault
        uint256 r0 = IERC20(token0).balanceOf(address(this));
        uint256 r1 = IERC20(token1).balanceOf(address(this));
        if (r0 > 0) IERC20(token0).safeTransfer(vault, r0);
        if (r1 > 0) IERC20(token1).safeTransfer(vault, r1);

        lastRebalance[vault] = block.timestamp;
    }

    /**
     * @inheritdoc IConcentratedLiquidityAdapter
     */
    function rebalanceWithCaps(
        address vault,
        int24 tickLower,
        int24 tickUpper,
        uint256 cap0,
        uint256 cap1
    ) external override returns (uint128 newLiquidity) {
        uint256 tokenId = _tokenId[vault];
        require(tokenId != 0, "PancakeV3Adapter: no position");
        require(!_isStaked(tokenId), "PancakeV3Adapter: position staked");

        // ---------------------------------------------------------------------
        // 1) Collect any outstanding fees to the adapter
        // ---------------------------------------------------------------------
        IPancakeV3NFPM(nfpm).collect(
            IPancakeV3NFPM.CollectParams({
                tokenId: tokenId,
                recipient: address(this),
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            })
        );

        // ---------------------------------------------------------------------
        // 2) Decrease all liquidity, collect owed tokens, and burn old NFT
        // ---------------------------------------------------------------------
        (, , , , , , , uint128 liq, , , , ) = IPancakeV3NFPM(nfpm).positions(
            tokenId
        );
        if (liq > 0) {
            IPancakeV3NFPM(nfpm).decreaseLiquidity(
                IPancakeV3NFPM.DecreaseLiquidityParams({
                    tokenId: tokenId,
                    liquidity: liq,
                    amount0Min: 0,
                    amount1Min: 0,
                    deadline: block.timestamp + 900
                })
            );
            IPancakeV3NFPM(nfpm).collect(
                IPancakeV3NFPM.CollectParams({
                    tokenId: tokenId,
                    recipient: address(this),
                    amount0Max: type(uint128).max,
                    amount1Max: type(uint128).max
                })
            );
        }

        IPancakeV3NFPM(nfpm).burn(tokenId);
        _tokenId[vault] = 0;

        // ---------------------------------------------------------------------
        // 3) Build final token amounts (caps + pull from vault if needed)
        // ---------------------------------------------------------------------
        (address token0, address token1) = tokens();
        uint256 bal0 = IERC20(token0).balanceOf(address(this));
        uint256 bal1 = IERC20(token1).balanceOf(address(this));

        uint256 want0 = (cap0 == 0) ? type(uint256).max : cap0;
        uint256 want1 = (cap1 == 0) ? type(uint256).max : cap1;

        uint256 use0 = bal0;
        uint256 use1 = bal1;

        // If we want more token0 than we currently have, pull from vault (up to its balance)
        if (want0 > use0) {
            uint256 deficit0 = want0 - use0;
            uint256 v0 = IERC20(token0).balanceOf(vault);
            uint256 pull0 = deficit0 > v0 ? v0 : deficit0;
            if (pull0 > 0) {
                IERC20(token0).safeTransferFrom(vault, address(this), pull0);
                use0 += pull0;
            }
        }

        // Same for token1
        if (want1 > use1) {
            uint256 deficit1 = want1 - use1;
            uint256 v1 = IERC20(token1).balanceOf(vault);
            uint256 pull1 = deficit1 > v1 ? v1 : deficit1;
            if (pull1 > 0) {
                IERC20(token1).safeTransferFrom(vault, address(this), pull1);
                use1 += pull1;
            }
        }

        // ---------------------------------------------------------------------
        // 4) Mint new position with final token amounts
        // ---------------------------------------------------------------------
        _approveIfNeeded(token0, nfpm, use0);
        _approveIfNeeded(token1, nfpm, use1);

        uint24 fee = IPancakeV3PoolMinimal(pool).fee();
        IPancakeV3NFPM.MintParams memory p = IPancakeV3NFPM.MintParams({
            token0: token0,
            token1: token1,
            fee: fee,
            tickLower: tickLower,
            tickUpper: tickUpper,
            amount0Desired: use0,
            amount1Desired: use1,
            amount0Min: 0,
            amount1Min: 0,
            recipient: address(this),
            deadline: block.timestamp + 900
        });

        (uint256 newTid, uint128 L, , ) = IPancakeV3NFPM(nfpm).mint(p);
        _tokenId[vault] = newTid;
        newLiquidity = L;

        // ---------------------------------------------------------------------
        // 5) Return leftovers to the vault
        // ---------------------------------------------------------------------
        uint256 r0 = IERC20(token0).balanceOf(address(this));
        uint256 r1 = IERC20(token1).balanceOf(address(this));
        if (r0 > 0) IERC20(token0).safeTransfer(vault, r0);
        if (r1 > 0) IERC20(token1).safeTransfer(vault, r1);

        lastRebalance[vault] = block.timestamp;
    }

    // -------------------------------------------------------------------------
    // Exit & Collect
    // -------------------------------------------------------------------------

    /**
     * @inheritdoc IConcentratedLiquidityAdapter
     */
    function exitPositionToVault(address vault) external override {
        uint256 tokenId = _tokenId[vault];
        if (tokenId == 0) return;
        require(!_isStaked(tokenId), "PancakeV3Adapter: position staked");

        // 1) Collect fees to adapter
        IPancakeV3NFPM(nfpm).collect(
            IPancakeV3NFPM.CollectParams({
                tokenId: tokenId,
                recipient: address(this),
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            })
        );

        // 2) Decrease all liquidity and collect owed tokens
        (, , , , , , , uint128 liq, , , , ) = IPancakeV3NFPM(nfpm).positions(
            tokenId
        );
        if (liq > 0) {
            IPancakeV3NFPM(nfpm).decreaseLiquidity(
                IPancakeV3NFPM.DecreaseLiquidityParams({
                    tokenId: tokenId,
                    liquidity: liq,
                    amount0Min: 0,
                    amount1Min: 0,
                    deadline: block.timestamp + 900
                })
            );
            IPancakeV3NFPM(nfpm).collect(
                IPancakeV3NFPM.CollectParams({
                    tokenId: tokenId,
                    recipient: address(this),
                    amount0Max: type(uint128).max,
                    amount1Max: type(uint128).max
                })
            );
        }

        // 3) Try to claim rewards (if any) before burning
        if (gauge != address(0)) {
            try this.claimRewards(vault) {} catch {}
        }

        // 4) Burn the NFT and send all tokens to the vault
        IPancakeV3NFPM(nfpm).burn(tokenId);
        _tokenId[vault] = 0;

        (address token0, address token1) = tokens();
        uint256 b0 = IERC20(token0).balanceOf(address(this));
        uint256 b1 = IERC20(token1).balanceOf(address(this));
        if (b0 > 0) IERC20(token0).safeTransfer(vault, b0);
        if (b1 > 0) IERC20(token1).safeTransfer(vault, b1);
    }

    /**
     * @inheritdoc IConcentratedLiquidityAdapter
     */
    function collectToVault(
        address vault
    ) external override returns (uint256 amount0, uint256 amount1) {
        uint256 tokenId = _tokenId[vault];
        if (tokenId == 0) return (0, 0);

        (amount0, amount1) = IPancakeV3NFPM(nfpm).collect(
            IPancakeV3NFPM.CollectParams({
                tokenId: tokenId,
                recipient: address(this),
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            })
        );

        (address token0, address token1) = tokens();
        if (amount0 > 0) IERC20(token0).safeTransfer(vault, amount0);
        if (amount1 > 0) IERC20(token1).safeTransfer(vault, amount1);
    }

    // -------------------------------------------------------------------------
    // Staking (MasterChefV3)
    // -------------------------------------------------------------------------

    /**
     * @inheritdoc IConcentratedLiquidityAdapter
     */
    function stakePosition(address vault) external override {
        if (gauge == address(0)) return;
        uint256 tokenId = _tokenId[vault];
        require(tokenId != 0, "PancakeV3Adapter: no position");

        IERC721(nfpm).safeTransferFrom(address(this), gauge, tokenId);
    }

    /**
     * @inheritdoc IConcentratedLiquidityAdapter
     */
    function unstakePosition(address vault) external override {
        if (gauge == address(0)) return;
        uint256 tokenId = _tokenId[vault];
        require(tokenId != 0, "PancakeV3Adapter: no position");

        // Best-effort: try claiming rewards before withdrawing
        try this.claimRewards(vault) {} catch {}

        IMasterChefV3(gauge).withdraw(tokenId, address(this));
    }

    /**
     * @inheritdoc IConcentratedLiquidityAdapter
     */
    function claimRewards(address vault) public override {
        if (gauge == address(0)) return;
        uint256 tokenId = _tokenId[vault];
        if (tokenId == 0) return;

        // Preferred path: claim directly to the vault
        try IMasterChefV3(gauge).harvest(tokenId, vault) {
            // success
        } catch {
            // Fallback: some deployments may require sending rewards to the adapter first
            uint256 beforeBal;
            address cake;

            try IMasterChefV3(gauge).CAKE() returns (address rt) {
                cake = rt;
                if (cake != address(0)) {
                    beforeBal = IERC20(cake).balanceOf(address(this));
                }
            } catch {
                // If CAKE() is not implemented, there is nothing else we can do
            }

            try IMasterChefV3(gauge).harvest(tokenId, address(this)) {
                if (cake != address(0)) {
                    uint256 gained = IERC20(cake).balanceOf(address(this)) -
                        beforeBal;
                    if (gained > 0) {
                        IERC20(cake).safeTransfer(vault, gained);
                    }
                }
            } catch {
                // If this also fails, we silently ignore to avoid breaking core flows.
            }
        }
    }
}
