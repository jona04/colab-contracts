// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {ProtocolFeeCollector} from "../src/core/ProtocolFeeCollector.sol";

/// @notice Deploys the ProtocolFeeCollector.
/// @dev Env:
///  - PRIVATE_KEY
///  - TREASURY (address)
///  - PROTOCOL_FEE_BPS (uint16, e.g. 1000 = 10%)
contract DeployProtocolFeeCollector is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address treasury = vm.envAddress("TREASURY");
        uint16 feeBps = uint16(vm.envUint("PROTOCOL_FEE_BPS"));

        vm.startBroadcast(pk);

        address owner = vm.addr(pk);
        ProtocolFeeCollector collector = new ProtocolFeeCollector(
            owner,
            treasury,
            feeBps
        );

        vm.stopBroadcast();

        console2.log("ProtocolFeeCollector deployed at:", address(collector));
        console2.log("Owner:", owner);
        console2.log("Treasury:", treasury);
        console2.log("ProtocolFeeBps:", feeBps);
    }
}
