// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ISwapRouterV3Pancake} from "../../src/interfaces/ISwapRouterV3Pancake.sol";

/**
 * @title MockRouterPancake
 * @notice Minimal mock of a PancakeV3-like router.
 * @dev
 * - Does not actually transfer tokens.
 * - Simply returns amountIn as amountOut for testing flow integration.
 * - Tracks the last call for assertions in tests.
 */
contract MockRouterPancake is ISwapRouterV3Pancake {
    /// @notice Whether exactInputSingle was ever called.
    bool public wasCalled;

    /// @notice Last caller of exactInputSingle.
    address public lastCaller;

    /// @notice Last tokenIn passed to exactInputSingle.
    address public lastTokenIn;

    /// @notice Last tokenOut passed to exactInputSingle.
    address public lastTokenOut;

    /// @notice Last amountIn passed to exactInputSingle.
    uint256 public lastAmountIn;

    function exactInputSingle(
        ExactInputSingleParams calldata params
    ) external payable override returns (uint256 amountOut) {
        // Track call for tests
        wasCalled = true;
        lastCaller = msg.sender;
        lastTokenIn = params.tokenIn;
        lastTokenOut = params.tokenOut;
        lastAmountIn = params.amountIn;

        // In a real router, tokens would be moved here.
        // For tests we only need a deterministic, non-reverting behavior.
        return params.amountIn;
    }
}
