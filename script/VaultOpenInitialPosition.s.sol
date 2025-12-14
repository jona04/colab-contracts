// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {ClientVault} from "../src/core/ClientVault.sol";

/// @notice Opens the initial CL position for a given vault using all idle balances.
/// @dev Env:
///  - PRIVATE_KEY (must be owner of vault)
///  - VAULT_ADDRESS
///  - LOWER_TICK (int)
///  - UPPER_TICK (int)
contract VaultOpenInitialPositionScript is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address vaultAddr = vm.envAddress("VAULT_ADDRESS");
        int24 lower = int24(int(vm.envInt("LOWER_TICK")));
        int24 upper = int24(int(vm.envInt("UPPER_TICK")));

        vm.startBroadcast(pk);

        ClientVault vault = ClientVault(vaultAddr);
        vault.openInitialPosition(lower, upper);

        vm.stopBroadcast();

        console2.log("Opened initial position:");
        console2.log("Vault:", vaultAddr);
        console2.log("Lower:", lower);
        console2.log("Upper:", upper);
    }
}
