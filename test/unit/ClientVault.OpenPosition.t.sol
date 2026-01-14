// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {ClientVault} from "../../src/core/ClientVault.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockAdapter} from "../mocks/MockAdapter.sol";
import {MockRouterPancake} from "../mocks/MockRouterPancake.sol";

contract ClientVaultOpenPositionTest is Test {
    ClientVault internal vault;
    MockERC20 internal token0;
    MockERC20 internal token1;
    MockAdapter internal adapter;
    MockRouterPancake internal router;

    address internal owner = address(0xA11CE);
    address internal executor = address(0xE1EC);
    address internal feeCollector = address(0); // allowed to be zero
    uint256 internal strategyId = 1;

    function setUp() public {
        // Deploy mock tokens
        token0 = new MockERC20("Token0", "T0");
        token1 = new MockERC20("Token1", "T1");

        // Deploy adapter & router
        adapter = new MockAdapter(address(token0), address(token1));
        router = new MockRouterPancake();

        // Mint tokens to the owner
        token0.mint(owner, 1_000e18);
        token1.mint(owner, 1_000e18);

        // Deploy the ClientVault with non-zero executor
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
    }

    /**
     * @notice Owner should be able to open the initial position when vault holds funds.
     */
    function testOpenInitialPosition() public {
        // 1) Move funds from owner to the vault
        vm.startPrank(owner);
        token0.transfer(address(vault), 500e18);
        token1.transfer(address(vault), 500e18);

        // 2) Open initial position with a simple range
        vault.openInitialPosition(-100, 100);
        vm.stopPrank();

        // 3) Assert that the vault tracked the new positionId
        assertEq(
            vault.positionTokenId(),
            1,
            "positionTokenId should be 1 after the first openInitialPosition"
        );

        // 4) (optional) Also check the adapter state for the vault address
        assertEq(
            adapter.currentTokenId(address(vault)),
            1,
            "Adapter should store tokenId=1 for the vault"
        );
    }

    /**
     * @notice Calling openInitialPosition without funds in the vault must revert.
     */
    function testOpenInitialPositionWithoutFundsReverts() public {
        // Owner does NOT transfer any tokens to the vault here

        vm.startPrank(owner);
        vm.expectRevert("ClientVault: no funds");
        vault.openInitialPosition(-100, 100);
        vm.stopPrank();
    }
}
