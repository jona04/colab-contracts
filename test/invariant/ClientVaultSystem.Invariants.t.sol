// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "forge-std/StdInvariant.sol";

import {ClientVault} from "../../src/core/ClientVault.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockAdapter} from "../mocks/MockAdapter.sol";
import {MockRouterPancake} from "../mocks/MockRouterPancake.sol";

/**
 * @title ClientVaultSystemInvariants
 * @notice Invariant tests for a simplified ClientVault system.
 * @dev
 *  Scenario:
 *  - One ClientVault.
 *  - One MockAdapter (no real AMM).
 *  - One MockRouterPancake (no real swaps).
 *  - Two ERC20 tokens.
 *
 *  Goals:
 *  - Ensure executor never ends up holding tokens.
 *  - Ensure total token supply is conserved across the main actors.
 *  - Ensure dexRouter binding in ClientVault stays immutable.
 */
contract ClientVaultSystemInvariants is StdInvariant, Test {
    ClientVault internal vault;
    MockAdapter internal adapter;
    MockRouterPancake internal router;
    MockERC20 internal token0;
    MockERC20 internal token1;

    address internal vaultOwner = address(0xA11CA);
    address internal executor = address(0xA11CB);
    address internal feeCollector = address(0xA11CC);
    uint256 internal strategyId = 1;

    uint256 internal initialSupply0 = 1_000_000e18;
    uint256 internal initialSupply1 = 1_000_000e18;

    Handler internal handler;

    function setUp() public {
        // Deploy tokens
        token0 = new MockERC20("Token0", "T0");
        token1 = new MockERC20("Token1", "T1");

        // Mint all supply to owner
        token0.mint(vaultOwner, initialSupply0);
        token1.mint(vaultOwner, initialSupply1);

        // Deploy adapter and router
        adapter = new MockAdapter(address(token0), address(token1));
        router = new MockRouterPancake();

        // Deploy vault
        vault = new ClientVault(
            vaultOwner,
            executor,
            address(adapter),
            address(router),
            feeCollector,
            strategyId,
            60, // cooldownSec
            100, // maxSlippageBps
            true // allowSwap
        );

        // Deploy handler that will perform random actions
        handler = new Handler(
            vault,
            adapter,
            router,
            token0,
            token1,
            vaultOwner,
            executor
        );

        // Let the invariant engine call functions on handler
        targetContract(address(handler));
    }

    // -------------------------------------------------------------------------
    // Invariants
    // -------------------------------------------------------------------------

    /**
     * @notice Invariant: executor should never hold any of the strategy tokens.
     * @dev
     *  If this invariant breaks, it means there is a code path where automation
     *  can siphon tokens out of the vault.
     */
    function invariant_ExecutorNeverHoldsTokens() public {
        assertEq(
            token0.balanceOf(executor),
            0,
            "Executor must never receive token0"
        );
        assertEq(
            token1.balanceOf(executor),
            0,
            "Executor must never receive token1"
        );
    }

    /**
     * @notice Invariant: total token supply is conserved among the main actors.
     * @dev
     *  Since the mocks do not mint or burn tokens after setup, the sum of balances
     *  across owner + vault + adapter + feeCollector + router must remain equal to
     *  the initial supply.
     */
    function invariant_TotalTokenSupplyConserved() public {
        // token0
        uint256 sum0 = token0.balanceOf(vaultOwner) +
            token0.balanceOf(address(vault)) +
            token0.balanceOf(address(adapter)) +
            token0.balanceOf(feeCollector) +
            token0.balanceOf(address(router));

        assertEq(
            sum0,
            initialSupply0,
            "Total supply of token0 must be conserved across main actors"
        );

        // token1
        uint256 sum1 = token1.balanceOf(vaultOwner) +
            token1.balanceOf(address(vault)) +
            token1.balanceOf(address(adapter)) +
            token1.balanceOf(feeCollector) +
            token1.balanceOf(address(router));

        assertEq(
            sum1,
            initialSupply1,
            "Total supply of token1 must be conserved across main actors"
        );
    }

    /**
     * @notice Invariant: ClientVault's dexRouter must remain immutable.
     * @dev
     *  This ensures that there is no code path which changes the router binding,
     *  which could otherwise redirect swaps to a malicious contract.
     */
    function invariant_DexRouterIsFixed() public {
        assertEq(
            vault.dexRouter(),
            address(router),
            "Vault dexRouter binding must not change"
        );
    }
}

/**
 * @title Handler
 * @notice Fuzz entrypoint for invariant testing.
 * @dev
 *  Exposes a subset of ClientVault operations using both owner and executor,
 *  with randomized parameters, to stress the contract state space.
 */
contract Handler is Test {
    ClientVault internal vault;
    MockAdapter internal adapter;
    MockRouterPancake internal router;
    MockERC20 internal token0;
    MockERC20 internal token1;

    address internal owner;
    address internal executor;

    constructor(
        ClientVault vault_,
        MockAdapter adapter_,
        MockRouterPancake router_,
        MockERC20 token0_,
        MockERC20 token1_,
        address owner_,
        address executor_
    ) {
        vault = vault_;
        adapter = adapter_;
        router = router_;
        token0 = token0_;
        token1 = token1_;
        owner = owner_;
        executor = executor_;
    }

    // -------------------------------------------------------------------------
    // Owner actions
    // -------------------------------------------------------------------------

    /**
     * @notice Owner deposits some amount of token0 and token1 into the vault.
     * @dev The handler chooses an amount based on the fuzzed input and clamps
     *      it by the owner's current balance.
     */
    function deposit(uint256 amount0, uint256 amount1) external {
        amount0 = bound(amount0, 0, token0.balanceOf(owner));
        amount1 = bound(amount1, 0, token1.balanceOf(owner));

        if (amount0 > 0) {
            vm.startPrank(owner);
            token0.transfer(address(vault), amount0);
            vm.stopPrank();
        }

        if (amount1 > 0) {
            vm.startPrank(owner);
            token1.transfer(address(vault), amount1);
            vm.stopPrank();
        }
    }

    /**
     * @notice Owner opens the initial position with a basic range.
     * @dev We do not care about the exact range; we just want the flow to execute.
     */
    function openPosition(int24 lower, int24 upper) external {
        // Ensure valid ordering
        if (lower >= upper) {
            (lower, upper) = (int24(-100), int24(100));
        }

        vm.startPrank(owner);
        // If there are no funds, this may revert; we ignore failures.
        try vault.openInitialPosition(lower, upper) {} catch {}
        vm.stopPrank();
    }

    /**
     * @notice Owner rebalances with arbitrary caps.
     */
    function rebalance(
        int24 lower,
        int24 upper,
        uint256 cap0,
        uint256 cap1
    ) external {
        if (lower >= upper) {
            (lower, upper) = (int24(-200), int24(200));
        }

        vm.startPrank(owner);
        try vault.rebalanceWithCaps(lower, upper, cap0, cap1) {} catch {}
        vm.stopPrank();
    }

    /**
     * @notice Owner exits the position and keeps funds in the vault.
     */
    function exitToVault() external {
        vm.startPrank(owner);
        try vault.exitPositionToVault() {} catch {}
        vm.stopPrank();
    }

    /**
     * @notice Owner exits the position and withdraws everything back.
     */
    function exitAndWithdraw() external {
        vm.startPrank(owner);
        try vault.exitPositionAndWithdrawAll(owner) {} catch {}
        vm.stopPrank();
    }

    // -------------------------------------------------------------------------
    // Executor actions
    // -------------------------------------------------------------------------

    /**
     * @notice Executor performs an automated rebalance with Pancake-style params.
     * @dev
     *  Uses a fixed range and small swapAmountIn to avoid excessive reverts.
     */
    function autoRebalance(
        uint256 swapAmountIn,
        uint256 swapAmountOutMin
    ) external {
        // clamp swapAmountIn to something reasonable
        swapAmountIn = bound(swapAmountIn, 0, 1_000e18);
        swapAmountOutMin = bound(swapAmountOutMin, 0, swapAmountIn);

        ClientVault.AutoRebalanceParams memory p = ClientVault
            .AutoRebalanceParams({
                newLower: -100,
                newUpper: 100,
                fee: 3000,
                tokenIn: address(token0),
                tokenOut: address(token1),
                swapAmountIn: swapAmountIn,
                swapAmountOutMin: swapAmountOutMin,
                sqrtPriceLimitX96: 0
            });

        vm.startPrank(executor);
        try vault.autoRebalancePancake(p) {} catch {}
        vm.stopPrank();
    }
}
