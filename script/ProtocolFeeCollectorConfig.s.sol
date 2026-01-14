// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {ProtocolFeeCollector} from "../src/core/ProtocolFeeCollector.sol";

/// @notice Sets or unsets an authorized reporter on ProtocolFeeCollector.
/// @dev Env:
///  - PRIVATE_KEY (collector owner)
///  - FEE_COLLECTOR_ADDRESS
///  - REPORTER_ADDRESS
///  - AUTHORIZED (bool)
contract ProtocolFeeCollectorSetReporterScript is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address collectorAddr = vm.envAddress("FEE_COLLECTOR_ADDRESS");
        address reporter = vm.envAddress("REPORTER_ADDRESS");
        bool authorized = vm.envBool("AUTHORIZED");

        vm.startBroadcast(pk);

        ProtocolFeeCollector collector = ProtocolFeeCollector(collectorAddr);
        collector.setReporter(reporter, authorized);

        vm.stopBroadcast();

        console2.log("Reporter updated:");
        console2.log("Collector:", collectorAddr);
        console2.log("Reporter:", reporter);
        console2.log("Authorized:", authorized);
    }
}
