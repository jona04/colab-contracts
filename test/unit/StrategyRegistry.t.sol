// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import {StrategyRegistry} from "../../src/core/StrategyRegistry.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";

/**
 * @title StrategyRegistryTest
 * @notice Unit tests for StrategyRegistry.
 */
contract StrategyRegistryTest is Test {
    StrategyRegistry internal registry;

    address internal owner = address(0xA0FFEE);
    address internal other = address(0xB0FFEE);

    address internal adapter = address(0xC0FFEE);
    address internal dexRouter = address(0xD0FFEE);
    address internal token0 = address(0xE0FFEE);
    address internal token1 = address(0xF0FFEE);

    function setUp() public {
        vm.prank(owner);
        registry = new StrategyRegistry(owner);
    }

    // -------------------------------------------------------------------------
    // Register
    // -------------------------------------------------------------------------

    function testRegisterStrategySuccess() public {
        string memory name = "Pancake CAKE/USDC";
        string memory description = "Tight-range delta-balanced strategy";

        vm.prank(owner);
        uint256 strategyId = registry.registerStrategy(
            adapter,
            dexRouter,
            token0,
            token1,
            name,
            description
        );

        assertEq(strategyId, 1, "First strategyId should be 1");
        assertEq(
            registry.nextStrategyId(),
            2,
            "nextStrategyId should increment"
        );

        StrategyRegistry.Strategy memory s = registry.getStrategy(strategyId);
        assertEq(s.adapter, adapter, "Adapter should be stored correctly");
        assertEq(s.dexRouter, dexRouter, "Router should be stored correctly");
        assertEq(s.token0, token0, "Token0 should be stored correctly");
        assertEq(s.token1, token1, "Token1 should be stored correctly");
        assertEq(s.active, true, "New strategy should be active by default");
        assertEq(
            keccak256(bytes(s.name)),
            keccak256(bytes(name)),
            "Name should match"
        );
        assertEq(
            keccak256(bytes(s.description)),
            keccak256(bytes(description)),
            "Description should match"
        );
    }

    function testRegisterStrategyRequiresOwner() public {
        vm.prank(other);
        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                other
            )
        );
        registry.registerStrategy(adapter, dexRouter, token0, token1, "x", "y");
    }

    function testRegisterStrategyZeroAddressesRevert() public {
        vm.startPrank(owner);

        vm.expectRevert("StrategyRegistry: adapter=0");
        registry.registerStrategy(
            address(0),
            dexRouter,
            token0,
            token1,
            "x",
            "y"
        );

        vm.expectRevert("StrategyRegistry: dexRouter=0");
        registry.registerStrategy(
            adapter,
            address(0),
            token0,
            token1,
            "x",
            "y"
        );

        vm.expectRevert("StrategyRegistry: tokens=0");
        registry.registerStrategy(
            adapter,
            dexRouter,
            address(0),
            token1,
            "x",
            "y"
        );

        vm.expectRevert("StrategyRegistry: tokens=0");
        registry.registerStrategy(
            adapter,
            dexRouter,
            token0,
            address(0),
            "x",
            "y"
        );

        vm.stopPrank();
    }

    // -------------------------------------------------------------------------
    // getStrategy & isStrategyActive
    // -------------------------------------------------------------------------

    function testGetStrategyUnknownReverts() public {
        vm.expectRevert("StrategyRegistry: unknown strategy");
        registry.getStrategy(999);
    }

    function testIsStrategyActiveReflectsState() public {
        vm.prank(owner);
        uint256 id = registry.registerStrategy(
            adapter,
            dexRouter,
            token0,
            token1,
            "n",
            "d"
        );

        assertTrue(
            registry.isStrategyActive(id),
            "New strategy should be active"
        );

        vm.prank(owner);
        registry.setStrategyActive(id, false);
        assertFalse(
            registry.isStrategyActive(id),
            "Strategy should be inactive after deactivation"
        );

        vm.prank(owner);
        registry.setStrategyActive(id, true);
        assertTrue(
            registry.isStrategyActive(id),
            "Strategy should be active again after reactivation"
        );
    }

    // -------------------------------------------------------------------------
    // updateStrategy
    // -------------------------------------------------------------------------

    function testUpdateStrategySuccess() public {
        vm.prank(owner);
        uint256 id = registry.registerStrategy(
            adapter,
            dexRouter,
            token0,
            token1,
            "name",
            "desc"
        );

        address newAdapter = address(0xA0FFEE);
        address newRouter = address(0xC0DFEE);
        address newToken0 = address(0xC0FFEE);
        address newToken1 = address(0xDEAD);
        string memory newName = "Updated strategy";
        string memory newDesc = "Updated description";

        vm.prank(owner);
        registry.updateStrategy(
            id,
            newAdapter,
            newRouter,
            newToken0,
            newToken1,
            newName,
            newDesc
        );

        StrategyRegistry.Strategy memory s = registry.getStrategy(id);
        assertEq(s.adapter, newAdapter, "Adapter should be updated");
        assertEq(s.dexRouter, newRouter, "Router should be updated");
        assertEq(s.token0, newToken0, "Token0 should be updated");
        assertEq(s.token1, newToken1, "Token1 should be updated");
        assertEq(
            keccak256(bytes(s.name)),
            keccak256(bytes(newName)),
            "Name should be updated"
        );
        assertEq(
            keccak256(bytes(s.description)),
            keccak256(bytes(newDesc)),
            "Description should be updated"
        );
        assertTrue(s.active, "Active flag should be preserved");
    }

    function testUpdateStrategyUnknownReverts() public {
        vm.prank(owner);
        vm.expectRevert("StrategyRegistry: unknown strategy");
        registry.updateStrategy(
            999,
            adapter,
            dexRouter,
            token0,
            token1,
            "x",
            "y"
        );
    }

    function testUpdateStrategyRequiresOwner() public {
        vm.prank(owner);
        uint256 id = registry.registerStrategy(
            adapter,
            dexRouter,
            token0,
            token1,
            "name",
            "desc"
        );

        vm.prank(other);
        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                other
            )
        );
        registry.updateStrategy(
            id,
            adapter,
            dexRouter,
            token0,
            token1,
            "x",
            "y"
        );
    }

    function testUpdateStrategyZeroAddressesRevert() public {
        vm.prank(owner);
        uint256 id = registry.registerStrategy(
            adapter,
            dexRouter,
            token0,
            token1,
            "name",
            "desc"
        );

        vm.startPrank(owner);

        vm.expectRevert("StrategyRegistry: adapter=0");
        registry.updateStrategy(
            id,
            address(0),
            dexRouter,
            token0,
            token1,
            "x",
            "y"
        );

        vm.expectRevert("StrategyRegistry: dexRouter=0");
        registry.updateStrategy(
            id,
            adapter,
            address(0),
            token0,
            token1,
            "x",
            "y"
        );

        vm.expectRevert("StrategyRegistry: tokens=0");
        registry.updateStrategy(
            id,
            adapter,
            dexRouter,
            address(0),
            token1,
            "x",
            "y"
        );

        vm.expectRevert("StrategyRegistry: tokens=0");
        registry.updateStrategy(
            id,
            adapter,
            dexRouter,
            token0,
            address(0),
            "x",
            "y"
        );

        vm.stopPrank();
    }

    // -------------------------------------------------------------------------
    // setStrategyActive
    // -------------------------------------------------------------------------

    function testSetStrategyActiveUnknownReverts() public {
        vm.prank(owner);
        vm.expectRevert("StrategyRegistry: unknown strategy");
        registry.setStrategyActive(999, true);
    }

    function testSetStrategyActiveRequiresOwner() public {
        vm.prank(owner);
        uint256 id = registry.registerStrategy(
            adapter,
            dexRouter,
            token0,
            token1,
            "n",
            "d"
        );

        vm.prank(other);
        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                other
            )
        );
        registry.setStrategyActive(id, false);
    }
}
