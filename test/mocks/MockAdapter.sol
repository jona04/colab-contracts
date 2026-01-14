// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import {IConcentratedLiquidityAdapter} from "../../src/interfaces/IConcentratedLiquidityAdapter.sol";

/**
 * @title MockAdapter
 * @notice Minimal mock implementation of IConcentratedLiquidityAdapter.
 * @dev
 * - Does NOT implement real CL math, only tracks a synthetic tokenId/liquidity per vault.
 * - Tokens are NOT actually moved; this is enough for logic & invariant tests that focus
 *   on wiring, access control and call flow rather than AMM math.
 */
contract MockAdapter is IConcentratedLiquidityAdapter {
    using SafeERC20 for IERC20;

    address public immutable override pool;
    address public immutable override nfpm;
    address public immutable override gauge;

    address private _token0;
    address private _token1;

    uint256 internal _nextId = 1;
    mapping(address => uint256) internal _tokenId;
    mapping(address => uint128) internal _liquidity;

    constructor(address token0_, address token1_) {
        require(
            token0_ != address(0) && token1_ != address(0),
            "MockAdapter: tokens=0"
        );
        _token0 = token0_;
        _token1 = token1_;
        pool = address(this); // dummy
        nfpm = address(this); // dummy
        gauge = address(0); // no staking in this mock
    }

    // ---------------------------------------------------------------------
    // Views
    // ---------------------------------------------------------------------

    function tokens()
        external
        view
        override
        returns (address token0, address token1)
    {
        return (_token0, _token1);
    }

    function tickSpacing() external pure override returns (int24) {
        return 60;
    }

    function slot0()
        external
        pure
        override
        returns (uint160 sqrtPriceX96, int24 tick)
    {
        return (1e18, 0);
    }

    function currentTokenId(
        address vault
    ) external view override returns (uint256) {
        return _tokenId[vault];
    }

    // ---------------------------------------------------------------------
    // Core LP methods (mocked)
    // ---------------------------------------------------------------------

    function openInitialPosition(
        address vault,
        int24 /*tickLower*/,
        int24 /*tickUpper*/
    ) external override returns (uint256 tokenId, uint128 liquidity) {
        require(_tokenId[vault] == 0, "MockAdapter: already opened");

        tokenId = _nextId++;
        liquidity = 1e18; // arbitrary non-zero value to indicate "there is liquidity"

        _tokenId[vault] = tokenId;
        _liquidity[vault] = liquidity;
    }

    function rebalanceWithCaps(
        address vault,
        int24 /*tickLower*/,
        int24 /*tickUpper*/,
        uint256 /*cap0*/,
        uint256 /*cap1*/
    ) external override returns (uint128 newLiquidity) {
        require(_tokenId[vault] != 0, "MockAdapter: no position");

        // For the mock, we just bump the tokenId and set a new liquidity.
        _tokenId[vault] = _nextId++;
        newLiquidity = 2e18;
        _liquidity[vault] = newLiquidity;
    }

    function exitPositionToVault(address vault) external override {
        // In the mock, just clear the tokenId and liquidity.
        _tokenId[vault] = 0;
        _liquidity[vault] = 0;
    }

    function collectToVault(
        address /*vault*/
    ) external pure override returns (uint256 amount0, uint256 amount1) {
        // No real fees in the mock
        return (0, 0);
    }

    function stakePosition(address /*vault*/) external pure override {
        // no-op in mock
    }

    function unstakePosition(address /*vault*/) external pure override {
        // no-op in mock
    }

    function claimRewards(address /*vault*/) external pure override {
        // no-op in mock
    }
}
