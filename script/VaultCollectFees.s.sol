// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {ClientVault} from "../src/core/ClientVault.sol";

/// @notice Collects fees from adapter into the vault.
/// @dev Env:
///  - PRIVATE_KEY (must be owner)
///  - VAULT_ADDRESS
contract VaultCollectFeesScript is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address vaultAddr = vm.envAddress("VAULT_ADDRESS");

        vm.startBroadcast(pk);

        ClientVault vault = ClientVault(vaultAddr);
        (uint256 a0, uint256 a1) = vault.collectToVault();

        vm.stopBroadcast();

        console2.log("Collected fees into vault:");
        console2.log("Vault:", vaultAddr);
        console2.log("Amount0:", a0);
        console2.log("Amount1:", a1);
    }
}
