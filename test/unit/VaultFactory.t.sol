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
 * @notice Unit tests for VaultFactory (owner-scoped strategies).
 */
contract VaultFactoryTest is Test {
    VaultFactory internal factory;
    StrategyRegistry internal registry;

    MockERC20 internal token0;
    MockERC20 internal token1;
    MockAdapter internal adapter;
    MockRouterPancake internal router;

    address internal factoryOwner = address(0xA11CE);
    address internal protocolOwner = factoryOwner;

    address internal globalExecutor = address(0xE1EC);
    address internal feeCollector = address(0xFEE5);

    address internal user = address(0xBEEF);
    address internal other = address(0xCAFE);

    uint32 internal defaultCooldownSec = 60;
    uint16 internal defaultMaxSlippageBps = 100; // 1%
    bool internal defaultAllowSwap = true;

    function setUp() public {
        // Deploy tokens, adapter and router
        token0 = new MockERC20("Token0", "T0");
        token1 = new MockERC20("Token1", "T1");
        adapter = new MockAdapter(address(token0), address(token1));
        router = new MockRouterPancake();

        // Deploy registry + allowlist (protocolOwner)
        vm.startPrank(protocolOwner);
        registry = new StrategyRegistry(protocolOwner);
        registry.setAdapterAllowed(address(adapter), true);
        registry.setRouterAllowed(address(router), true);

        // Deploy factory
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

        // Register a base strategy for `user` (NOT for protocolOwner!)
        vm.prank(user);
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
    // Configuration (onlyOwner)
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
        assertEq(factory.executor(), newExecutor);
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
        assertEq(factory.feeCollector(), newCollector);
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

        assertEq(factory.defaultCooldownSec(), newCooldown);
        assertEq(factory.defaultMaxSlippageBps(), newSlippage);
        assertEq(factory.defaultAllowSwap(), newAllowSwap);
    }

    // -------------------------------------------------------------------------
    // Vault creation
    // -------------------------------------------------------------------------

    function testCreateClientVaultWithActiveStrategy() public {
        uint256 strategyId = 1;

        // ownerOverride = 0 -> vault owner == msg.sender (user)
        vm.prank(user);
        address vaultAddr = factory.createClientVault(strategyId, address(0));

        assertTrue(vaultAddr != address(0));

        // global indexing
        assertEq(factory.allVaultsLength(), 1);

        (address infoVault, address infoOwner, uint256 infoStrategyId) = factory
            .allVaults(0);
        assertEq(infoVault, vaultAddr);
        assertEq(infoOwner, user);
        assertEq(infoStrategyId, strategyId);

        // by owner
        address[] memory byOwner = factory.getVaultsByOwner(user);
        assertEq(byOwner.length, 1);
        assertEq(byOwner[0], vaultAddr);

        // by (owner, strategy)
        address[] memory byOwnerStrategy = factory.getVaultsByOwnerAndStrategy(
            user,
            strategyId
        );
        assertEq(byOwnerStrategy.length, 1);
        assertEq(byOwnerStrategy[0], vaultAddr);

        // introspect wiring
        ClientVault vault = ClientVault(vaultAddr);
        assertEq(vault.owner(), user);
        assertEq(vault.executor(), factory.executor());
        assertEq(address(vault.adapter()), address(adapter));
        assertEq(vault.dexRouter(), address(router));
        assertEq(vault.feeCollector(), factory.feeCollector());
        assertEq(vault.strategyId(), strategyId);
    }

    function testCreateClientVaultWithOwnerOverrideUsesOverrideForStrategyLookup()
        public
    {
        uint256 strategyId = 1;
        address explicitOwner = address(0xE1EC);

        // explicitOwner has NOT registered strategyId=1, so it must revert on registry.getStrategy(explicitOwner, 1)
        vm.prank(user);
        vm.expectRevert("StrategyRegistry: unknown strategy");
        factory.createClientVault(strategyId, explicitOwner);
    }

    function testCreateClientVaultWithOwnerOverrideSuccessWhenOwnerHasStrategy()
        public
    {
        uint256 strategyId = 1;
        address explicitOwner = address(0xE1EC);

        // register strategy for explicitOwner
        vm.prank(explicitOwner);
        registry.registerStrategy(
            address(adapter),
            address(router),
            address(token0),
            address(token1),
            "OwnerOverride Strategy",
            "d"
        );

        // create vault where ownerOverride == explicitOwner
        vm.prank(user);
        address vaultAddr = factory.createClientVault(
            strategyId,
            explicitOwner
        );

        ClientVault vault = ClientVault(vaultAddr);
        assertEq(vault.owner(), explicitOwner);

        address[] memory byOwner = factory.getVaultsByOwner(explicitOwner);
        assertEq(byOwner.length, 1);
        assertEq(byOwner[0], vaultAddr);

        address[] memory byOwnerStrategy = factory.getVaultsByOwnerAndStrategy(
            explicitOwner,
            strategyId
        );
        assertEq(byOwnerStrategy.length, 1);
        assertEq(byOwnerStrategy[0], vaultAddr);
    }

    function testCreateClientVaultFailsIfStrategyNotActive() public {
        uint256 strategyId = 1;

        vm.prank(user);
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

        vm.prank(user);
        factory.createClientVault(strategyId, address(0));

        assertEq(factory.allVaultsLength(), 2);
    }
}
