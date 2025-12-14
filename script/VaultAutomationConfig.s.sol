// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {ClientVault} from "../src/core/ClientVault.sol";

/// @notice Enables or disables automation on a vault.
/// @dev Env:
///  - PRIVATE_KEY (owner)
///  - VAULT_ADDRESS
///  - ENABLED (bool)
contract VaultToggleAutomationScript is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address vaultAddr = vm.envAddress("VAULT_ADDRESS");
        bool enabled = vm.envBool("ENABLED");

        vm.startBroadcast(pk);
        ClientVault(vaultAddr).setAutomationEnabled(enabled);
        vm.stopBroadcast();

        console2.log("Automation toggled:");
        console2.log("Vault:", vaultAddr);
        console2.log("Enabled:", enabled);
    }
}

/// @notice Updates automation config for a vault.
/// @dev Env:
///  - PRIVATE_KEY (owner)
///  - VAULT_ADDRESS
///  - COOLDOWN_SEC (uint32)
///  - MAX_SLIPPAGE_BPS (uint16)
///  - ALLOW_SWAP (bool)
contract VaultSetAutomationConfigScript is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address vaultAddr = vm.envAddress("VAULT_ADDRESS");
        uint32 cooldown = uint32(vm.envUint("COOLDOWN_SEC"));
        uint16 maxSlippage = uint16(vm.envUint("MAX_SLIPPAGE_BPS"));
        bool allowSwap = vm.envBool("ALLOW_SWAP");

        vm.startBroadcast(pk);
        ClientVault(vaultAddr).setAutomationConfig(
            cooldown,
            maxSlippage,
            allowSwap
        );
        vm.stopBroadcast();

        console2.log("Automation config updated:");
        console2.log("Vault:", vaultAddr);
        console2.log("CooldownSec:", cooldown);
        console2.log("MaxSlippageBps:", maxSlippage);
        console2.log("AllowSwap:", allowSwap);
    }
}
