// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

/// @notice Transfers ERC20 tokens from EOA to a given vault.
/// @dev Env:
///  - PRIVATE_KEY (must hold tokens)
///  - TOKEN_ADDRESS
///  - VAULT_ADDRESS
///  - AMOUNT (uint, raw units)
contract FundVaultWithTokens is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address token = vm.envAddress("TOKEN0_ADDRESS");
        address vault = vm.envAddress("VAULT_ADDRESS");
        uint256 amount = 0.001 * 1e18;

        vm.startBroadcast(pk);

        IERC20(token).transfer(vault, amount);

        vm.stopBroadcast();

        console2.log("Funded vault with tokens:");
        console2.log("Vault:", vault);
        console2.log("Token:", token);
        console2.log("Amount:", amount);
    }
}
