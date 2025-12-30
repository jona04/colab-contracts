// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/core/VaultFactory.sol";

/// @notice Script to update the global automation executor in VaultFactory.
contract VaultFactorySetExecutor is Script {
    function run() external {
        // Environment variables:
        // - VAULT_FACTORY: address of the deployed VaultFactory
        // - NEW_EXECUTOR: new executor EOA address
        // - PRIVATE_KEY: owner private key of the VaultFactory (protocol multisig key)
        address factory = vm.envAddress("VAULT_FACTORY");
        address newExecutor = vm.envAddress("NEW_EXECUTOR");
        uint256 pk = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(pk);

        VaultFactory(factory).setExecutor(newExecutor);

        vm.stopBroadcast();
    }
}
