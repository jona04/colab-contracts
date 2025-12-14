// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {StrategyRegistry} from "../src/core/StrategyRegistry.sol";

/// @notice Deploys the StrategyRegistry.
/// @dev Env:
///  - PRIVATE_KEY
contract DeployStrategyRegistry is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(pk);

        address owner = vm.addr(pk);
        StrategyRegistry registry = new StrategyRegistry(owner);

        vm.stopBroadcast();

        console2.log("StrategyRegistry deployed at:", address(registry));
        console2.log("Owner:", owner);
    }
}
