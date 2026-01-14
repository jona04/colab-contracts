// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {VaultFactory} from "../src/core/VaultFactory.sol";

/// @notice Deploys the VaultFactory.
/// @dev Env:
///  - PRIVATE_KEY
///  - STRATEGY_REGISTRY_ADDRESS
///  - EXECUTOR_ADDRESS
///  - FEE_COLLECTOR_ADDRESS (can be 0x0 if not used yet)
///  - DEFAULT_COOLDOWN_SEC (uint32)
///  - DEFAULT_MAX_SLIPPAGE_BPS (uint16)
///  - DEFAULT_ALLOW_SWAP (bool)
contract DeployVaultFactory is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address registry = vm.envAddress("STRATEGY_REGISTRY_ADDRESS");
        address executor = vm.envAddress("EXECUTOR_ADDRESS");
        address feeCollector = vm.envAddress("FEE_COLLECTOR_ADDRESS");
        uint32 cooldown = uint32(vm.envUint("DEFAULT_COOLDOWN_SEC"));
        uint16 maxSlippage = uint16(vm.envUint("DEFAULT_MAX_SLIPPAGE_BPS"));
        bool allowSwap = vm.envBool("DEFAULT_ALLOW_SWAP");

        vm.startBroadcast(pk);

        address owner = vm.addr(pk);
        VaultFactory factory = new VaultFactory(
            owner,
            registry,
            executor,
            feeCollector,
            cooldown,
            maxSlippage,
            allowSwap
        );

        vm.stopBroadcast();

        console2.log("VaultFactory deployed at:", address(factory));
        console2.log("Owner:", owner);
        console2.log("StrategyRegistry:", registry);
        console2.log("Executor:", executor);
        console2.log("FeeCollector:", feeCollector);
    }
}
