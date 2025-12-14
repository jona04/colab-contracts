// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import {VaultFactory} from "../../src/core/VaultFactory.sol";
import {StrategyRegistry} from "../../src/core/StrategyRegistry.sol";
import {ClientVault} from "../../src/core/ClientVault.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockAdapter} from "../mocks/MockAdapter.sol";
import {MockRouterPancake} from "../mocks/MockRouterPancake.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";

/**
 * @title VaultFactoryTest
 * @notice Unit tests for VaultFactory.
 */
contract VaultFactoryTest is Test {
    VaultFactory internal factory;
    StrategyRegistry internal registry;

    MockERC20 internal token0;
    MockERC20 internal token1;
    MockAdapter internal adapter;
    MockRouterPancake internal router;

    address internal factoryOwner = address(0xA11CE);
    address internal strategyOwner = factoryOwner;
    address internal globalExecutor = address(0xE1EC);
    address internal feeCollector = address(0xFEE5);
    address internal user = address(0xBEEF);
    address internal other = address(0xCAFE);

    uint32 internal defaultCooldownSec = 60;
    uint16 internal defaultMaxSlippageBps = 100; // 1%
    bool internal defaultAllowSwap = true;

    function setUp() public {
        // Deploy registry and factory under factoryOwner
        vm.startPrank(factoryOwner);
        registry = new StrategyRegistry(strategyOwner);
        factory = new VaultFactory(
            factoryOwner,
            address(registry),
            globalExecutor,
            feeCollector,
            defaultCooldownSec,
            defaultMaxSlippageBps,
            defaultAllowSwap
        );
        vm.stopPrank();

        // Deploy tokens, adapter and router
        token0 = new MockERC20("Token0", "T0");
        token1 = new MockERC20("Token1", "T1");
        adapter = new MockAdapter(address(token0), address(token1));
        router = new MockRouterPancake();

        // Register a base strategy
        vm.prank(strategyOwner);
        registry.registerStrategy(
            address(adapter),
            address(router),
            address(token0),
            address(token1),
            "Pancake T0/T1",
            "Simple test strategy"
        );
    }

    // -------------------------------------------------------------------------
    // Configuration
    // -------------------------------------------------------------------------

    function testSetExecutorOnlyOwner() public {
        address newExecutor = address(0x1234);

        vm.prank(other);
        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                other
            )
        );
        factory.setExecutor(newExecutor);

        vm.prank(factoryOwner);
        factory.setExecutor(newExecutor);
        assertEq(
            factory.executor(),
            newExecutor,
            "Executor should be updated by factory owner"
        );
    }

    function testSetExecutorZeroAddressReverts() public {
        vm.prank(factoryOwner);
        vm.expectRevert("VaultFactory: executor=0");
        factory.setExecutor(address(0));
    }

    function testSetFeeCollectorOnlyOwner() public {
        address newCollector = address(0xC0FFEE);

        vm.prank(other);
        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                other
            )
        );
        factory.setFeeCollector(newCollector);

        vm.prank(factoryOwner);
        factory.setFeeCollector(newCollector);
        assertEq(
            factory.feeCollector(),
            newCollector,
            "Fee collector should be updated"
        );
    }

    function testSetDefaultsOnlyOwner() public {
        uint32 newCooldown = 120;
        uint16 newSlippage = 250;
        bool newAllowSwap = false;

        vm.prank(other);
        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                other
            )
        );
        factory.setDefaults(newCooldown, newSlippage, newAllowSwap);

        vm.prank(factoryOwner);
        factory.setDefaults(newCooldown, newSlippage, newAllowSwap);

        assertEq(
            factory.defaultCooldownSec(),
            newCooldown,
            "Cooldown default should be updated"
        );
        assertEq(
            factory.defaultMaxSlippageBps(),
            newSlippage,
            "Slippage default should be updated"
        );
        assertEq(
            factory.defaultAllowSwap(),
            newAllowSwap,
            "AllowSwap default should be updated"
        );
    }

    // -------------------------------------------------------------------------
    // Vault creation
    // -------------------------------------------------------------------------

    function testCreateClientVaultWithActiveStrategy() public {
        uint256 strategyId = 1; // first registered

        // msg.sender is user; ownerOverride = address(0) so the vault owner == user
        vm.prank(user);
        address vaultAddr = factory.createClientVault(strategyId, address(0));

        assertTrue(vaultAddr != address(0), "Vault address should be non-zero");

        // Check global indexing
        assertEq(
            factory.allVaultsLength(),
            1,
            "There should be exactly one vault recorded"
        );

        (address infoVault, address infoOwner, uint256 infoStrategyId) = factory
            .allVaults(0);

        assertEq(
            infoVault,
            vaultAddr,
            "VaultInfo should store correct vault address"
        );
        assertEq(infoOwner, user, "VaultInfo should store correct owner");
        assertEq(
            infoStrategyId,
            strategyId,
            "VaultInfo should store correct strategyId"
        );

        // Check vaultsByOwner mapping
        address[] memory byOwner = factory.getVaultsByOwner(user);
        assertEq(byOwner.length, 1, "User should have exactly one vault");
        assertEq(
            byOwner[0],
            vaultAddr,
            "VaultsByOwner should point to the created vault"
        );

        // Check vaultsByStrategy mapping
        address[] memory byStrategy = factory.getVaultsByStrategy(strategyId);
        assertEq(
            byStrategy.length,
            1,
            "Strategy should have exactly one vault"
        );
        assertEq(
            byStrategy[0],
            vaultAddr,
            "VaultsByStrategy should point to the created vault"
        );

        // Introspect wiring on the deployed ClientVault
        ClientVault vault = ClientVault(vaultAddr);
        assertEq(
            vault.owner(),
            user,
            "ClientVault.owner should be wired as user"
        );
        assertEq(
            vault.executor(),
            factory.executor(),
            "ClientVault.executor should be wired from factory"
        );
        assertEq(
            address(vault.adapter()),
            address(adapter),
            "ClientVault.adapter should come from StrategyRegistry"
        );
        assertEq(
            vault.dexRouter(),
            address(router),
            "ClientVault.dexRouter should come from StrategyRegistry"
        );
        assertEq(
            vault.feeCollector(),
            factory.feeCollector(),
            "ClientVault.feeCollector should match factory"
        );
        assertEq(
            vault.strategyId(),
            strategyId,
            "ClientVault.strategyId should match parameter"
        );
    }

    function testCreateClientVaultWithOwnerOverride() public {
        uint256 strategyId = 1;
        address explicitOwner = address(0xE1EC);

        vm.prank(user); // creator
        address vaultAddr = factory.createClientVault(
            strategyId,
            explicitOwner
        );

        ClientVault vault = ClientVault(vaultAddr);
        assertEq(
            vault.owner(),
            explicitOwner,
            "ClientVault.owner should respect explicit ownerOverride"
        );
    }

    function testCreateClientVaultFailsIfStrategyNotActive() public {
        uint256 strategyId = 1;

        // Deactivate strategy in registry
        vm.prank(strategyOwner);
        registry.setStrategyActive(strategyId, false);

        vm.prank(user);
        vm.expectRevert("VaultFactory: strategy not active");
        factory.createClientVault(strategyId, address(0));
    }

    // -------------------------------------------------------------------------
    // Views
    // -------------------------------------------------------------------------

    function testAllVaultsLengthReflectsCount() public {
        uint256 strategyId = 1;

        vm.prank(user);
        factory.createClientVault(strategyId, address(0));

        vm.prank(other);
        factory.createClientVault(strategyId, address(0));

        assertEq(
            factory.allVaultsLength(),
            2,
            "allVaultsLength should reflect number of created vaults"
        );
    }
}
