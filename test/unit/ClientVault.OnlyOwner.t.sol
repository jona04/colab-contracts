// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {ClientVault} from "../../src/core/ClientVault.sol";
import {MockERC20} from "../../test/mocks/MockERC20.sol";
import {MockAdapter} from "../../test/mocks/MockAdapter.sol";
import {MockRouterPancake} from "../../test/mocks/MockRouterPancake.sol";

contract ClientVaultOnlyOwnerTest is Test {
    ClientVault internal vault;
    MockERC20 internal token0;
    MockERC20 internal token1;
    MockAdapter internal adapter;
    MockRouterPancake internal router;

    address internal owner = address(0xA11CE);
    address internal executor = address(0xE1EC);
    address internal feeCollector = address(0xFEE5);
    uint256 internal strategyId = 1;

    function setUp() public {
        token0 = new MockERC20("Token0", "T0");
        token1 = new MockERC20("Token1", "T1");
        adapter = new MockAdapter(address(token0), address(token1));
        router = new MockRouterPancake();

        // Mint tokens
        token0.mint(owner, 1_000e18);
        token1.mint(owner, 1_000e18);

        // Deploy the ClientVault
        vault = new ClientVault(
            owner,
            executor,
            address(adapter),
            address(router),
            feeCollector,
            strategyId,
            60, // cooldownSec
            100, // maxSlippageBps
            true // allowSwap
        );

        // 🔹 Fund the vault so withdraw actually has something to send
        vm.startPrank(owner);
        token0.transfer(address(vault), 100e18);
        token1.transfer(address(vault), 50e18);
        vm.stopPrank();
    }

    function testOnlyOwnerCanWithdraw() public {
        uint256 initialBalance0 = token0.balanceOf(owner);
        uint256 initialBalance1 = token1.balanceOf(owner);

        vm.startPrank(owner);
        vault.exitPositionAndWithdrawAll(owner);
        vm.stopPrank();

        assertEq(
            token0.balanceOf(owner),
            initialBalance0 + 100e18,
            "Owner should receive token0 from vault"
        );
        assertEq(
            token1.balanceOf(owner),
            initialBalance1 + 50e18,
            "Owner should receive token1 from vault"
        );
        assertEq(
            token0.balanceOf(address(vault)),
            0,
            "Vault must be drained of token0 after withdraw"
        );
        assertEq(
            token1.balanceOf(address(vault)),
            0,
            "Vault must be drained of token1 after withdraw"
        );
    }

    function testExecutorCannotWithdraw() public {
        vm.startPrank(executor);
        vm.expectRevert(bytes("ClientVault: not owner"));
        vault.exitPositionAndWithdrawAll(executor);
        vm.stopPrank();
    }

    function testExecutorCannotCallOwnerFunctions() public {
        // openInitialPosition
        vm.prank(executor);
        vm.expectRevert(bytes("ClientVault: not owner"));
        vault.openInitialPosition(0, 0);

        // rebalanceWithCaps
        vm.prank(executor);
        vm.expectRevert(bytes("ClientVault: not owner"));
        vault.rebalanceWithCaps(0, 0, 0, 0);

        // exitPositionToVault
        vm.prank(executor);
        vm.expectRevert(bytes("ClientVault: not owner"));
        vault.exitPositionToVault();

        // collectToVault
        vm.prank(executor);
        vm.expectRevert(bytes("ClientVault: not owner"));
        vault.collectToVault();

        // stake
        vm.prank(executor);
        vm.expectRevert(bytes("ClientVault: not owner"));
        vault.stake();

        // unstake
        vm.prank(executor);
        vm.expectRevert(bytes("ClientVault: not owner"));
        vault.unstake();

        // claimRewards
        vm.prank(executor);
        vm.expectRevert(bytes("ClientVault: not owner"));
        vault.claimRewards();

        // setAutomationEnabled
        vm.prank(executor);
        vm.expectRevert(bytes("ClientVault: not owner"));
        vault.setAutomationEnabled(true);

        // setAutomationConfig
        vm.prank(executor);
        vm.expectRevert(bytes("ClientVault: not owner"));
        vault.setAutomationConfig(10, 100, true);
    }
}
