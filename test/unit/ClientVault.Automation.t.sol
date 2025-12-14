// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {ClientVault} from "../../src/core/ClientVault.sol";
import {MockERC20} from "../../test/mocks/MockERC20.sol";
import {MockAdapter} from "../../test/mocks/MockAdapter.sol";
import {MockRouterPancake} from "../../test/mocks/MockRouterPancake.sol";

contract ClientVaultAutomationTest is Test {
    ClientVault internal vault;
    MockERC20 internal token0;
    MockERC20 internal token1;
    MockAdapter internal adapter;
    MockRouterPancake internal router;

    address internal owner = address(0xA11CE);
    address internal executor = address(0xE1EC);
    uint256 internal strategyId = 1;

    function setUp() public {
        // Coloca o tempo bem à frente para não bater no cooldown inicial
        vm.warp(1_000);

        token0 = new MockERC20("Token0", "T0");
        token1 = new MockERC20("Token1", "T1");
        adapter = new MockAdapter(address(token0), address(token1));
        router = new MockRouterPancake();

        // Mint tokens to owner
        token0.mint(owner, 1_000e18);
        token1.mint(owner, 1_000e18);

        // Deploy the ClientVault with a NON-zero executor
        vault = new ClientVault(
            owner,
            executor, // <- NOTE: use executor, not address(0)
            address(adapter),
            address(router),
            address(0),
            strategyId,
            60, // cooldownSec
            100, // maxSlippageBps
            true // allowSwap
        );

        // Move some funds into the vault so that _openWithAllIdle does not revert
        vm.startPrank(owner);
        token0.transfer(address(vault), 100e18);
        token1.transfer(address(vault), 50e18);
        vm.stopPrank();
    }

    // ---------------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------------

    function _enableAutomation() internal {
        vm.prank(owner);
        vault.setAutomationEnabled(true);
    }

    // ---------------------------------------------------------------------
    // 1) Automation: automationEnabled, cooldown, allowSwap
    // ---------------------------------------------------------------------

    function testAutoRebalanceRequiresAutomationEnabled() public {
        // By default automationEnabled = false
        ClientVault.AutoRebalanceParams memory params = ClientVault
            .AutoRebalanceParams({
                newLower: -100,
                newUpper: 100,
                fee: 500,
                tokenIn: address(token0),
                tokenOut: address(token1),
                swapAmountIn: 0,
                swapAmountOutMin: 0,
                sqrtPriceLimitX96: 0
            });

        vm.prank(executor);
        vm.expectRevert(bytes("ClientVault: automation disabled"));
        vault.autoRebalancePancake(params);
    }

    function testAutoRebalanceRespectsCooldown() public {
        _enableAutomation();

        // Set cooldown to 100s
        vm.prank(owner);
        vault.setAutomationConfig(100, 100, true);

        ClientVault.AutoRebalanceParams memory params = ClientVault
            .AutoRebalanceParams({
                newLower: -100,
                newUpper: 100,
                fee: 500,
                tokenIn: address(token0),
                tokenOut: address(token1),
                swapAmountIn: 0,
                swapAmountOutMin: 0,
                sqrtPriceLimitX96: 0
            });

        // First rebalance: ok
        vm.prank(executor);
        vault.autoRebalancePancake(params);

        // Advance less than cooldown
        vm.warp(block.timestamp + 50);

        // Second rebalance must fail due to cooldown
        vm.prank(executor);
        vm.expectRevert(bytes("ClientVault: cooldown"));
        vault.autoRebalancePancake(params);
    }

    function testAutoRebalanceSwapDisabledCannotSwap() public {
        _enableAutomation();

        // Disable swaps
        vm.prank(owner);
        vault.setAutomationConfig(0, 100, false);

        ClientVault.AutoRebalanceParams memory params = ClientVault
            .AutoRebalanceParams({
                newLower: -100,
                newUpper: 100,
                fee: 500,
                tokenIn: address(token0),
                tokenOut: address(token1),
                swapAmountIn: 1e18, // try to swap
                swapAmountOutMin: 0,
                sqrtPriceLimitX96: 0
            });

        vm.prank(executor);
        vm.expectRevert(bytes("ClientVault: swap disabled"));
        vault.autoRebalancePancake(params);
    }

    function testAutoRebalanceTokenMismatchReverts() public {
        _enableAutomation();

        // Token that is not part of adapter's pair
        address randomToken = address(0xDEAD);

        ClientVault.AutoRebalanceParams memory params = ClientVault
            .AutoRebalanceParams({
                newLower: -100,
                newUpper: 100,
                fee: 500,
                tokenIn: randomToken,
                tokenOut: address(token1),
                swapAmountIn: 0,
                swapAmountOutMin: 0,
                sqrtPriceLimitX96: 0
            });

        vm.prank(executor);
        vm.expectRevert(bytes("ClientVault: tokens mismatch"));
        vault.autoRebalancePancake(params);
    }

    function testAutoRebalanceHappyPathNoSwap() public {
        _enableAutomation();

        ClientVault.AutoRebalanceParams memory params = ClientVault
            .AutoRebalanceParams({
                newLower: -100,
                newUpper: 100,
                fee: 500,
                tokenIn: address(token0),
                tokenOut: address(token1),
                swapAmountIn: 0, // no swap
                swapAmountOutMin: 0,
                sqrtPriceLimitX96: 0
            });

        vm.prank(executor);
        vault.autoRebalancePancake(params);

        // cooldownSec initial is 60, so lastRebalanceTs should have been set.
        (bool enabled, uint32 cooldown, , ) = vault.getAutomationConfig();
        assertTrue(enabled, "automation should be enabled");
        assertEq(cooldown, 60, "cooldown should remain 60");
    }

    // ---------------------------------------------------------------------
    // 2) Router interaction: swap must use dexRouter
    // ---------------------------------------------------------------------

    function testAutoRebalanceWithSwapUsesConfiguredRouter() public {
        _enableAutomation();

        // Explicitly allow swaps
        vm.prank(owner);
        vault.setAutomationConfig(0, 100, true);

        ClientVault.AutoRebalanceParams memory params = ClientVault
            .AutoRebalanceParams({
                newLower: -100,
                newUpper: 100,
                fee: 500,
                tokenIn: address(token0),
                tokenOut: address(token1),
                swapAmountIn: 10e18, // > 0 => will call router
                swapAmountOutMin: 0,
                sqrtPriceLimitX96: 0
            });

        vm.prank(executor);
        vault.autoRebalancePancake(params);

        // Assert router interaction
        assertTrue(router.wasCalled(), "router should have been called");
        assertEq(
            router.lastCaller(),
            address(vault),
            "vault must be the caller of router"
        );
        assertEq(router.lastTokenIn(), address(token0), "tokenIn mismatch");
        assertEq(router.lastTokenOut(), address(token1), "tokenOut mismatch");
        assertEq(router.lastAmountIn(), 10e18, "swap amount mismatch");
    }
}
