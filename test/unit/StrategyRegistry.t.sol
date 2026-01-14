// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import {StrategyRegistry} from "../../src/core/StrategyRegistry.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";

/**
 * @title StrategyRegistryTest
 * @notice Unit tests for StrategyRegistry (per-owner strategies + protocol allowlists).
 */
contract StrategyRegistryTest is Test {
    StrategyRegistry internal registry;

    address internal protocolOwner = address(0xA0FFEE);
    address internal userA = address(0xB0FFEE);
    address internal userB = address(0xC0FFEE);

    address internal adapter = address(0x1111);
    address internal adapter2 = address(0x2222);

    address internal router = address(0xAAAA);
    address internal router2 = address(0xBBBB);

    address internal token0 = address(0xE0FFEE);
    address internal token1 = address(0xF0FFEE);

    function setUp() public {
        vm.prank(protocolOwner);
        registry = new StrategyRegistry(protocolOwner);

        // allowlist adapter/router (protocol level)
        vm.startPrank(protocolOwner);
        registry.setAdapterAllowed(adapter, true);
        registry.setAdapterAllowed(adapter2, true);
        registry.setRouterAllowed(router, true);
        registry.setRouterAllowed(router2, true);
        vm.stopPrank();
    }

    // -------------------------------------------------------------------------
    // allowlists
    // -------------------------------------------------------------------------

    function testAllowlistOnlyOwner() public {
        vm.prank(userA);
        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                userA
            )
        );
        registry.setAdapterAllowed(adapter, true);

        vm.prank(userA);
        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                userA
            )
        );
        registry.setRouterAllowed(router, true);
    }

    function testAllowlistZeroAddressReverts() public {
        vm.prank(protocolOwner);
        vm.expectRevert("StrategyRegistry: adapter=0");
        registry.setAdapterAllowed(address(0), true);

        vm.prank(protocolOwner);
        vm.expectRevert("StrategyRegistry: router=0");
        registry.setRouterAllowed(address(0), true);
    }

    // -------------------------------------------------------------------------
    // registerStrategy
    // -------------------------------------------------------------------------

    function testRegisterStrategySuccess_MsgSenderScoped() public {
        string memory name = "Pancake CAKE/USDC";
        string memory description = "Tight-range delta-balanced strategy";

        vm.prank(userA);
        uint256 strategyId = registry.registerStrategy(
            adapter,
            router,
            token0,
            token1,
            name,
            description
        );

        assertEq(strategyId, 1, "first per-owner id must be 1");
        assertEq(
            registry.nextStrategyIdByOwner(userA),
            2,
            "nextStrategyIdByOwner should increment"
        );

        StrategyRegistry.Strategy memory s = registry.getStrategy(
            userA,
            strategyId
        );

        assertEq(s.adapter, adapter);
        assertEq(s.dexRouter, router);
        assertEq(s.token0, token0);
        assertEq(s.token1, token1);
        assertTrue(s.active);

        assertEq(keccak256(bytes(s.name)), keccak256(bytes(name)));
        assertEq(
            keccak256(bytes(s.description)),
            keccak256(bytes(description))
        );

        // enumeration
        uint256[] memory ids = registry.getStrategyIdsByOwner(userA);
        assertEq(ids.length, 1);
        assertEq(ids[0], 1);

        assertEq(registry.strategiesLengthByOwner(userA), 1);
    }

    function testRegisterStrategyPerOwnerCounterIndependence() public {
        vm.prank(userA);
        uint256 a1 = registry.registerStrategy(
            adapter,
            router,
            token0,
            token1,
            "A1",
            "d"
        );
        vm.prank(userA);
        uint256 a2 = registry.registerStrategy(
            adapter2,
            router2,
            token0,
            token1,
            "A2",
            "d"
        );

        vm.prank(userB);
        uint256 b1 = registry.registerStrategy(
            adapter,
            router,
            token0,
            token1,
            "B1",
            "d"
        );

        assertEq(a1, 1);
        assertEq(a2, 2);
        assertEq(b1, 1);
    }

    function testRegisterStrategyRequiresAllowlist() public {
        address notAllowedAdapter = address(0xDEAD);
        address notAllowedRouter = address(0xBEEF);

        // adapter not allowed
        vm.prank(userA);
        vm.expectRevert("StrategyRegistry: adapter not allowed");
        registry.registerStrategy(
            notAllowedAdapter,
            router,
            token0,
            token1,
            "x",
            "y"
        );

        // router not allowed
        vm.prank(userA);
        vm.expectRevert("StrategyRegistry: router not allowed");
        registry.registerStrategy(
            adapter,
            notAllowedRouter,
            token0,
            token1,
            "x",
            "y"
        );
    }

    function testRegisterStrategyZeroAddressesRevert() public {
        vm.startPrank(userA);

        vm.expectRevert("StrategyRegistry: adapter=0");
        registry.registerStrategy(address(0), router, token0, token1, "x", "y");

        vm.expectRevert("StrategyRegistry: router=0");
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
            router,
            address(0),
            token1,
            "x",
            "y"
        );

        vm.expectRevert("StrategyRegistry: tokens=0");
        registry.registerStrategy(
            adapter,
            router,
            token0,
            address(0),
            "x",
            "y"
        );

        vm.stopPrank();
    }

    function testRegisterStrategyIdenticalTokensRevert() public {
        vm.prank(userA);
        vm.expectRevert("StrategyRegistry: identical tokens");
        registry.registerStrategy(adapter, router, token0, token0, "x", "y");
    }

    // -------------------------------------------------------------------------
    // getStrategy / getMyStrategy / isStrategyActive
    // -------------------------------------------------------------------------

    function testGetStrategyUnknownReverts() public {
        vm.expectRevert("StrategyRegistry: unknown strategy");
        registry.getStrategy(userA, 999);
    }

    function testGetMyStrategyWorks() public {
        vm.prank(userA);
        uint256 id = registry.registerStrategy(
            adapter,
            router,
            token0,
            token1,
            "n",
            "d"
        );

        vm.prank(userA);
        StrategyRegistry.Strategy memory s = registry.getMyStrategy(id);
        assertEq(s.adapter, adapter);
        assertTrue(s.active);
    }

    function testIsStrategyActiveReflectsState() public {
        vm.prank(userA);
        uint256 id = registry.registerStrategy(
            adapter,
            router,
            token0,
            token1,
            "n",
            "d"
        );

        assertTrue(registry.isStrategyActive(userA, id));

        vm.prank(userA);
        registry.setStrategyActive(id, false);
        assertFalse(registry.isStrategyActive(userA, id));

        vm.prank(userA);
        registry.setStrategyActive(id, true);
        assertTrue(registry.isStrategyActive(userA, id));
    }

    // -------------------------------------------------------------------------
    // updateStrategy
    // -------------------------------------------------------------------------

    function testUpdateStrategySuccess() public {
        vm.prank(userA);
        uint256 id = registry.registerStrategy(
            adapter,
            router,
            token0,
            token1,
            "name",
            "desc"
        );

        vm.prank(userA);
        registry.updateStrategy(
            id,
            adapter2,
            router2,
            token0,
            token1,
            "Updated",
            "Updated desc"
        );

        StrategyRegistry.Strategy memory s = registry.getStrategy(userA, id);
        assertEq(s.adapter, adapter2);
        assertEq(s.dexRouter, router2);
        assertEq(keccak256(bytes(s.name)), keccak256(bytes("Updated")));
        assertEq(
            keccak256(bytes(s.description)),
            keccak256(bytes("Updated desc"))
        );
        assertTrue(s.active, "active flag must be preserved");
    }

    function testUpdateStrategyUnknownReverts() public {
        vm.prank(userA);
        vm.expectRevert("StrategyRegistry: unknown strategy");
        registry.updateStrategy(999, adapter, router, token0, token1, "x", "y");
    }

    function testUpdateStrategyRequiresAllowlist() public {
        vm.prank(userA);
        uint256 id = registry.registerStrategy(
            adapter,
            router,
            token0,
            token1,
            "name",
            "desc"
        );

        vm.prank(protocolOwner);
        registry.setAdapterAllowed(adapter2, false);

        vm.prank(userA);
        vm.expectRevert("StrategyRegistry: adapter not allowed");
        registry.updateStrategy(id, adapter2, router, token0, token1, "x", "y");
    }

    function testUpdateStrategyZeroAddressesRevert() public {
        vm.prank(userA);
        uint256 id = registry.registerStrategy(
            adapter,
            router,
            token0,
            token1,
            "name",
            "desc"
        );

        vm.startPrank(userA);

        vm.expectRevert("StrategyRegistry: adapter=0");
        registry.updateStrategy(
            id,
            address(0),
            router,
            token0,
            token1,
            "x",
            "y"
        );

        vm.expectRevert("StrategyRegistry: router=0");
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
            router,
            address(0),
            token1,
            "x",
            "y"
        );

        vm.expectRevert("StrategyRegistry: tokens=0");
        registry.updateStrategy(
            id,
            adapter,
            router,
            token0,
            address(0),
            "x",
            "y"
        );

        vm.stopPrank();
    }

    function testUpdateStrategyIdenticalTokensRevert() public {
        vm.prank(userA);
        uint256 id = registry.registerStrategy(
            adapter,
            router,
            token0,
            token1,
            "name",
            "desc"
        );

        vm.prank(userA);
        vm.expectRevert("StrategyRegistry: identical tokens");
        registry.updateStrategy(id, adapter, router, token0, token0, "x", "y");
    }

    // -------------------------------------------------------------------------
    // setStrategyActive
    // -------------------------------------------------------------------------

    function testSetStrategyActiveUnknownReverts() public {
        vm.prank(userA);
        vm.expectRevert("StrategyRegistry: unknown strategy");
        registry.setStrategyActive(999, true);
    }
}
