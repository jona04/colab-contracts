// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {ClientVault} from "../../src/core/ClientVault.sol";
import {MockERC20} from "../../test/mocks/MockERC20.sol";
import {MockAdapter} from "../../test/mocks/MockAdapter.sol";
import {MockRouterPancake} from "../../test/mocks/MockRouterPancake.sol";

contract ClientVaultRebalanceTest is Test {
    ClientVault internal vault;
    MockERC20 internal token0;
    MockERC20 internal token1;
    MockAdapter internal adapter;
    MockRouterPancake internal router;

    address internal owner = address(0xA11CE);
    address internal executor = address(0xE1EC);
    uint256 internal strategyId = 1;

    function setUp() public {
        // Time avançado só pra ficar consistente com outros testes
        vm.warp(1_000);

        token0 = new MockERC20("Token0", "T0");
        token1 = new MockERC20("Token1", "T1");
        adapter = new MockAdapter(address(token0), address(token1));
        router = new MockRouterPancake();

        // Mint tokens
        token0.mint(owner, 1_000e18);
        token1.mint(owner, 1_000e18);

        vault = new ClientVault(
            owner,
            executor,
            address(adapter),
            address(router),
            address(0),
            strategyId,
            60, // cooldownSec
            100, // maxSlippageBps
            true // allowSwap
        );

        // 🔹 Fund the vault and open the initial position
        vm.startPrank(owner);
        token0.transfer(address(vault), 500e18);
        token1.transfer(address(vault), 500e18);
        vault.openInitialPosition(-100, 100);
        vm.stopPrank();

        // Sanity: first open should give tokenId = 1 in our MockAdapter
        assertEq(
            vault.positionTokenId(),
            1,
            "Initial positionTokenId should be 1"
        );
        assertEq(
            adapter.currentTokenId(address(vault)),
            1,
            "Adapter should track tokenId=1 after first open"
        );
    }

    function testRebalanceWithCaps() public {
        uint256 beforeId = vault.positionTokenId();

        vm.startPrank(owner);
        vault.rebalanceWithCaps(-200, 200, 100e18, 50e18);
        vm.stopPrank();

        uint256 afterId = vault.positionTokenId();

        assertEq(beforeId, 1, "Before rebalance, tokenId should be 1");
        assertEq(afterId, 2, "After rebalance, tokenId should be updated to 2");
        assertEq(
            adapter.currentTokenId(address(vault)),
            afterId,
            "Adapter currentTokenId must match vault.positionTokenId"
        );
    }
}
