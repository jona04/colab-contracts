// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {VaultFactory} from "../src/core/VaultFactory.sol";

/// @notice Creates a new ClientVault for a given strategy.
/// @dev Env:
///  - PRIVATE_KEY (tx sender)
///  - VAULT_FACTORY_ADDRESS
///  - STRATEGY_ID (uint)
///  - OWNER_OVERRIDE (optional, can be 0x0000.. if you want msg.sender)
contract CreateClientVaultScript is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address factoryAddr = vm.envAddress("VAULT_FACTORY_ADDRESS");
        uint256 strategyId = vm.envUint("STRATEGY_ID");
        address ownerOverride = vm.envAddress("OWNER_OVERRIDE");

        vm.startBroadcast(pk);

        VaultFactory factory = VaultFactory(factoryAddr);
        address vault = factory.createClientVault(strategyId, ownerOverride);

        vm.stopBroadcast();

        console2.log("ClientVault created:");
        console2.log("Factory:", factoryAddr);
        console2.log("Vault:", vault);
        console2.log("StrategyId:", strategyId);
        console2.log("OwnerOverride:", ownerOverride);
    }
}
