// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {ClientVault} from "../src/core/ClientVault.sol";

/// @notice Calls autoRebalancePancake as the executor.
/// @dev Env:
///  - PRIVATE_KEY (must be the executor address configured in the vault)
///  - VAULT_ADDRESS
///  - NEW_LOWER_TICK (int)
///  - NEW_UPPER_TICK (int)
///  - FEE (uint24)
///  - TOKEN_IN_ADDRESS
///  - TOKEN_OUT_ADDRESS
///  - SWAP_AMOUNT_IN (uint, 0 = no swap)
///  - SWAP_MIN_OUT (uint)
///  - SQRT_PRICE_LIMIT_X96 (uint160, usually 0)
contract ExecutorAutoRebalancePancakeScript is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address vaultAddr = vm.envAddress("VAULT_ADDRESS");
        int24 lower = int24(int(vm.envInt("NEW_LOWER_TICK")));
        int24 upper = int24(int(vm.envInt("NEW_UPPER_TICK")));
        uint24 fee = uint24(vm.envUint("FEE"));
        address tokenIn = vm.envAddress("TOKEN_IN_ADDRESS");
        address tokenOut = vm.envAddress("TOKEN_OUT_ADDRESS");
        uint256 swapIn = vm.envUint("SWAP_AMOUNT_IN");
        uint256 minOut = vm.envUint("SWAP_MIN_OUT");
        uint160 sqrtLimit = uint160(vm.envUint("SQRT_PRICE_LIMIT_X96"));

        ClientVault.AutoRebalanceParams memory params = ClientVault
            .AutoRebalanceParams({
                newLower: lower,
                newUpper: upper,
                fee: fee,
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                swapAmountIn: swapIn,
                swapAmountOutMin: minOut,
                sqrtPriceLimitX96: sqrtLimit
            });

        vm.startBroadcast(pk);

        ClientVault vault = ClientVault(vaultAddr);
        vault.autoRebalancePancake(params);

        vm.stopBroadcast();

        console2.log("autoRebalancePancake executed:");
        console2.log("Vault:", vaultAddr);
        console2.log("Lower:", lower);
        console2.log("Upper:", upper);
        console2.log("SwapIn:", swapIn);
        console2.log("MinOut:", minOut);
    }
}
