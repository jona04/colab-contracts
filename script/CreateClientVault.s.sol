// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {VaultFactory} from "../src/core/VaultFactory.sol";

/// @notice Creates a new ClientVault for a given strategy.
/// @dev Env:
///  - PRIVATE_KEY (tx sender)
///  - VAULT_FACTORY_ADDRESS
///  - STRATEGY_ID (uint) // per-owner strategy id
///  - OWNER_OVERRIDE (optional; if omitted or 0x0, uses msg.sender)
contract CreateClientVault is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address factoryAddr = vm.envAddress("VAULT_FACTORY_ADDRESS");
        uint256 strategyId = vm.envUint("STRATEGY_ID");
        address ownerOverride = vm.envOr("OWNER_OVERRIDE", address(0));

        vm.startBroadcast(pk);

        VaultFactory factory = VaultFactory(factoryAddr);
        address vault = factory.createClientVault(strategyId, ownerOverride);

        vm.stopBroadcast();

        address vaultOwner = (ownerOverride != address(0))
            ? ownerOverride
            : vm.addr(pk);

        console2.log("ClientVault created:");
        console2.log("Factory:", factoryAddr);
        console2.log("Vault:", vault);
        console2.log("StrategyId (per-owner):", strategyId);
        console2.log("VaultOwner:", vaultOwner);
        console2.log("OwnerOverride:", ownerOverride);
    }
}
