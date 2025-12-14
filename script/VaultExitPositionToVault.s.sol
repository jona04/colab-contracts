// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {ClientVault} from "../src/core/ClientVault.sol";

/// @notice Exits the position, keeping tokens inside the vault.
/// @dev Env:
///  - PRIVATE_KEY (must be owner)
///  - VAULT_ADDRESS
contract VaultExitPositionToVaultScript is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address vaultAddr = vm.envAddress("VAULT_ADDRESS");

        vm.startBroadcast(pk);

        ClientVault vault = ClientVault(vaultAddr);
        vault.exitPositionToVault();

        vm.stopBroadcast();

        console2.log("Position exited to vault:");
        console2.log("Vault:", vaultAddr);
    }
}
