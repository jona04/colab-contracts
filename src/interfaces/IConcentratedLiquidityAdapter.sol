// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IConcentratedLiquidityAdapter
 * @notice Generic interface for a concentrated-liquidity adapter (Uniswap v3, Pancake v3, Aerodrome Slipstream, etc.).
 * @dev
 * - The adapter is responsible for:
 *     * Holding the LP NFT (position) for each vault.
 *     * Pulling tokens from the vault when opening/rebalancing.
 *     * Pushing tokens back to the vault when exiting or collecting.
 * - The vault (ClientVault) is responsible for all higher-level risk logic:
 *     * When to rebalance, what ranges to use, how much to allocate.
 *     * Automation cooldowns, slippage limits, etc.
 * - This interface must be implemented by each protocol-specific adapter.
 */
interface IConcentratedLiquidityAdapter {
    // -------------------------------------------------------------------------
    // Immutable protocol wiring
    // -------------------------------------------------------------------------

    /**
     * @notice Returns the underlying CL pool address.
     */
    function pool() external view returns (address);

    /**
     * @notice Returns the Non-Fungible Position Manager address (NFT LP manager).
     */
    function nfpm() external view returns (address);

    /**
     * @notice Returns the gauge / staking contract address (if any).
     * @dev May be zero address if no staking is used.
     */
    function gauge() external view returns (address);

    // -------------------------------------------------------------------------
    // Basic views
    // -------------------------------------------------------------------------

    /**
     * @notice Returns the underlying token pair (token0, token1) for the pool.
     */
    function tokens() external view returns (address token0, address token1);

    /**
     * @notice Returns the pool tick spacing.
     */
    function tickSpacing() external view returns (int24);

    /**
     * @notice Returns current pool price info (sqrtPriceX96, tick).
     */
    function slot0() external view returns (uint160 sqrtPriceX96, int24 tick);

    /**
     * @notice Returns the current LP NFT id (if any) assigned to a given vault.
     * @param vault Vault address owning the position.
     */
    function currentTokenId(address vault) external view returns (uint256);

    // -------------------------------------------------------------------------
    // Core LP operations
    // -------------------------------------------------------------------------

    /**
     * @notice Open an initial concentrated-liquidity position for a vault.
     * @dev
     * - The adapter is expected to:
     *     * Read token0/token1 balances from the vault.
     *     * Transfer those tokens into the adapter.
     *     * Mint an LP NFT and keep it under the adapter.
     *     * Return any unused tokens back to the vault.
     * - Implementations MAY assume the vault has `approve`d this adapter
     *   to pull tokens through ERC-20 `transferFrom`.
     * @param vault Vault address on behalf of which the position is opened.
     * @param tickLower Lower bound of the price range.
     * @param tickUpper Upper bound of the price range.
     * @return tokenId Newly created LP NFT id.
     * @return liquidity Final liquidity amount for the minted position.
     */
    function openInitialPosition(
        address vault,
        int24 tickLower,
        int24 tickUpper
    ) external returns (uint256 tokenId, uint128 liquidity);

    /**
     * @notice Rebalance an existing position for a vault with upper caps for additional capital.
     * @dev
     * - Typical implementation:
     *     * Collect fees to the adapter.
     *     * Decrease liquidity fully and collect owed tokens.
     *     * Burn the old NFT.
     *     * Optionally pull more token0/token1 from the vault up to (cap0, cap1).
     *     * Mint a new position in the new range, returning unused tokens to the vault.
     * @param vault Vault address whose position will be rebalanced.
     * @param tickLower New lower bound of the price range.
     * @param tickUpper New upper bound of the price range.
     * @param cap0 Maximum additional token0 to pull from the vault (0 = no limit / use all).
     * @param cap1 Maximum additional token1 to pull from the vault (0 = no limit / use all).
     * @return newLiquidity Liquidity of the newly minted position.
     */
    function rebalanceWithCaps(
        address vault,
        int24 tickLower,
        int24 tickUpper,
        uint256 cap0,
        uint256 cap1
    ) external returns (uint128 newLiquidity);

    /**
     * @notice Exit the current position for a vault and return all tokens to the vault.
     * @dev
     * - Typical implementation:
     *     * Collect fees.
     *     * Decrease all liquidity, collect owed tokens.
     *     * Burn the NFT.
     *     * Transfer all token0/token1 balances held by the adapter for this position back to the vault.
     * - If there is no position for the vault, this function SHOULD simply return.
     * @param vault Vault address whose position will be closed.
     */
    function exitPositionToVault(address vault) external;

    /**
     * @notice Collect outstanding pool fees for a vault's position and push them to the vault.
     * @param vault Vault address whose position fees will be collected.
     * @return amount0 Amount of token0 sent to the vault.
     * @return amount1 Amount of token1 sent to the vault.
     */
    function collectToVault(
        address vault
    ) external returns (uint256 amount0, uint256 amount1);

    // -------------------------------------------------------------------------
    // Staking / rewards (optional)
    // -------------------------------------------------------------------------

    /**
     * @notice Stake the vault's LP NFT into the gauge / MasterChef (if any).
     * @dev If `gauge()` is zero address, implementation MAY simply return.
     * @param vault Vault address whose position will be staked.
     */
    function stakePosition(address vault) external;

    /**
     * @notice Unstake the LP NFT from the gauge / MasterChef (if any).
     * @dev If `gauge()` is zero address, implementation MAY simply return.
     * @param vault Vault address whose position will be unstaked.
     */
    function unstakePosition(address vault) external;

    /**
     * @notice Claim staking rewards for a vault's position and forward them to the vault.
     * @dev Implementations that cannot deliver rewards directly to the vault MAY
     *      route rewards through the adapter and then forward them to the vault.
     * @param vault Vault address whose rewards will be claimed.
     */
    function claimRewards(address vault) external;
}
