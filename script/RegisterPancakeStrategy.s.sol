// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {StrategyRegistry} from "../src/core/StrategyRegistry.sol";

/// @notice Registers a Pancake v3 strategy in StrategyRegistry.
/// @dev Env:
///  - PRIVATE_KEY (must be Owner of registry)
///  - STRATEGY_REGISTRY_ADDRESS
///  - ADAPTER_ADDRESS
///  - DEX_ROUTER_ADDRESS (Pancake Router v3)
///  - TOKEN0_ADDRESS
///  - TOKEN1_ADDRESS
///  - STRATEGY_NAME (string)
///  - STRATEGY_DESCRIPTION (string)
contract RegisterPancakeStrategy is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address registryAddr = vm.envAddress("STRATEGY_REGISTRY_ADDRESS");
        address adapter = vm.envAddress("ADAPTER_ADDRESS");
        address router = vm.envAddress("DEX_ROUTER_ADDRESS");
        address token0 = vm.envAddress("TOKEN0_ADDRESS");
        address token1 = vm.envAddress("TOKEN1_ADDRESS");
        string memory name = vm.envString("STRATEGY_NAME");
        string memory description = vm.envString("STRATEGY_DESCRIPTION");

        vm.startBroadcast(pk);

        StrategyRegistry registry = StrategyRegistry(registryAddr);
        uint256 strategyId = registry.registerStrategy(
            adapter,
            router,
            token0,
            token1,
            name,
            description
        );

        vm.stopBroadcast();

        console2.log("Strategy registered:");
        console2.log("StrategyRegistry:", registryAddr);
        console2.log("StrategyId:", strategyId);
        console2.log("Adapter:", adapter);
        console2.log("Router:", router);
        console2.log("token0:", token0);
        console2.log("token1:", token1);
    }
}
