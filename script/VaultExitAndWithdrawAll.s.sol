// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {ClientVault} from "../src/core/ClientVault.sol";

/// @notice Exits the position and withdraws all balances to a recipient.
/// @dev Env:
///  - PRIVATE_KEY (must be owner)
///  - VAULT_ADDRESS
///  - TO_ADDRESS (recipient of all balances)
contract VaultExitAndWithdrawAllScript is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address vaultAddr = vm.envAddress("VAULT_ADDRESS");
        address to = vm.envAddress("TO_ADDRESS");

        vm.startBroadcast(pk);

        ClientVault vault = ClientVault(vaultAddr);
        vault.exitPositionAndWithdrawAll(to);

        vm.stopBroadcast();

        console2.log("Position exited and all funds withdrawn:");
        console2.log("Vault:", vaultAddr);
        console2.log("To:", to);
    }
}
