// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {PancakeV3Adapter} from "../src/adapters/pancake/PancakeV3Adapter.sol";

/// @notice Deploys the PancakeV3Adapter for a specific pool.
/// @dev Env:
///  - PRIVATE_KEY
///  - PANCAKE_POOL_ADDRESS
///  - PANCAKE_NFPM_ADDRESS
///  - PANCAKE_MASTERCHEF_ADDRESS (can be 0x0 if no staking)
contract DeployPancakeV3Adapter is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address pool = vm.envAddress("PANCAKE_POOL_ADDRESS");
        address nfpm = vm.envAddress("PANCAKE_NFPM_ADDRESS");
        address masterChef = vm.envAddress("PANCAKE_MASTERCHEF_ADDRESS");

        vm.startBroadcast(pk);

        PancakeV3Adapter adapter = new PancakeV3Adapter(pool, nfpm, masterChef);

        vm.stopBroadcast();

        console2.log("PancakeV3Adapter deployed at:", address(adapter));
        console2.log("Pool:", pool);
        console2.log("NFPM:", nfpm);
        console2.log("MasterChefV3:", masterChef);
    }
}
