// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {ClientVault} from "../src/core/ClientVault.sol";

/// @notice Stakes the vault's LP position in the underlying gauge.
/// @dev Env:
///  - PRIVATE_KEY (owner)
///  - VAULT_ADDRESS
contract VaultStakeScript is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address vaultAddr = vm.envAddress("VAULT_ADDRESS");

        vm.startBroadcast(pk);
        ClientVault(vaultAddr).stake();
        vm.stopBroadcast();

        console2.log("Staked position for vault:", vaultAddr);
    }
}

/// @notice Unstakes the vault's LP position from the gauge.
/// @dev Env:
///  - PRIVATE_KEY (owner)
///  - VAULT_ADDRESS
contract VaultUnstakeScript is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address vaultAddr = vm.envAddress("VAULT_ADDRESS");

        vm.startBroadcast(pk);
        ClientVault(vaultAddr).unstake();
        vm.stopBroadcast();

        console2.log("Unstaked position for vault:", vaultAddr);
    }
}

/// @notice Claims rewards from the gauge for the vault.
/// @dev Env:
///  - PRIVATE_KEY (owner)
///  - VAULT_ADDRESS
contract VaultClaimRewardsScript is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address vaultAddr = vm.envAddress("VAULT_ADDRESS");

        vm.startBroadcast(pk);
        ClientVault(vaultAddr).claimRewards();
        vm.stopBroadcast();

        console2.log("Claimed rewards for vault:", vaultAddr);
    }
}
