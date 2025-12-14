// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";

/**
 * @title StrategyRegistry
 * @notice Registry of whitelisted strategies that can be used by ClientVaults.
 * @dev
 * - Controlled by the protocol owner (Colab).
 * - Each strategy binds:
 *     * a Concentrated Liquidity adapter implementation,
 *     * a DEX router,
 *     * the underlying token0/token1 pair,
 *     * human-readable metadata.
 * - The VaultFactory queries this registry to ensure a strategy is valid and active
 *   before deploying a new ClientVault.
 */
contract StrategyRegistry is Ownable {
    /// @notice Metadata describing a single strategy.
    struct Strategy {
        // Core wiring
        address adapter; // CL adapter bound to a specific pool/gauge
        address dexRouter; // DEX router to be used by ClientVaults
        // Underlying assets (for sanity checks / off-chain UX)
        address token0;
        address token1;
        // Human metadata (for dashboards / off-chain discovery)
        string name;
        string description;
        // Lifecycle
        bool active;
    }

    /// @notice Next strategy id to be assigned (starts at 1).
    uint256 public nextStrategyId = 1;

    /// @notice Mapping of strategy id => Strategy metadata.
    mapping(uint256 => Strategy) private _strategies;

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    /// @notice Emitted when a new strategy is registered.
    event StrategyRegistered(
        uint256 indexed strategyId,
        address indexed adapter,
        address indexed dexRouter,
        address token0,
        address token1,
        string name
    );

    /// @notice Emitted when a strategy is updated.
    event StrategyUpdated(
        uint256 indexed strategyId,
        address indexed adapter,
        address indexed dexRouter,
        address token0,
        address token1,
        string name
    );

    /// @notice Emitted when a strategy is activated or deactivated.
    event StrategyStatusChanged(uint256 indexed strategyId, bool active);

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    /**
     * @notice Construct a new StrategyRegistry.
     * @param initialOwner Address that will control this registry (typically a multisig).
     */
    constructor(address initialOwner) Ownable(initialOwner) {}

    // -------------------------------------------------------------------------
    // Public views
    // -------------------------------------------------------------------------

    /**
     * @notice Returns full metadata for a given strategy id.
     * @param strategyId Id of the strategy to query.
     * @return s Strategy struct.
     */
    function getStrategy(
        uint256 strategyId
    ) public view returns (Strategy memory s) {
        s = _strategies[strategyId];
        require(s.adapter != address(0), "StrategyRegistry: unknown strategy");
    }

    /**
     * @notice Checks if a strategy is currently active.
     * @param strategyId Id of the strategy.
     * @return True if the strategy exists and is active.
     */
    function isStrategyActive(uint256 strategyId) external view returns (bool) {
        Strategy memory s = _strategies[strategyId];
        return s.adapter != address(0) && s.active;
    }

    // -------------------------------------------------------------------------
    // Owner-only mutators
    // -------------------------------------------------------------------------

    /**
     * @notice Register a new strategy in the registry.
     * @dev
     * - Assigns a new incremental strategyId.
     * - Marks the strategy as active by default.
     * @param adapter CL adapter contract bound to the target pool/gauge.
     * @param dexRouter DEX router to be used by ClientVaults for swaps.
     * @param token0 Underlying token0 of the pool.
     * @param token1 Underlying token1 of the pool.
     * @param name Human-readable name (e.g. "Pancake CAKE/USDC Tight Range").
     * @param description Free-form description (e.g. JSON URI, IPFS hash, etc.).
     * @return strategyId Newly created strategy id.
     */
    function registerStrategy(
        address adapter,
        address dexRouter,
        address token0,
        address token1,
        string calldata name,
        string calldata description
    ) external onlyOwner returns (uint256 strategyId) {
        require(adapter != address(0), "StrategyRegistry: adapter=0");
        require(dexRouter != address(0), "StrategyRegistry: dexRouter=0");
        require(
            token0 != address(0) && token1 != address(0),
            "StrategyRegistry: tokens=0"
        );

        strategyId = nextStrategyId;
        nextStrategyId++;

        _strategies[strategyId] = Strategy({
            adapter: adapter,
            dexRouter: dexRouter,
            token0: token0,
            token1: token1,
            name: name,
            description: description,
            active: true
        });

        emit StrategyRegistered(
            strategyId,
            adapter,
            dexRouter,
            token0,
            token1,
            name
        );
    }

    /**
     * @notice Update metadata of an existing strategy (adapter/router/tokens/metadata).
     * @dev Does not change the active flag.
     * @param strategyId Strategy id to be updated.
     * @param adapter New adapter address.
     * @param dexRouter New router address.
     * @param token0 New token0.
     * @param token1 New token1.
     * @param name New name.
     * @param description New description.
     */
    function updateStrategy(
        uint256 strategyId,
        address adapter,
        address dexRouter,
        address token0,
        address token1,
        string calldata name,
        string calldata description
    ) external onlyOwner {
        Strategy storage s = _strategies[strategyId];
        require(s.adapter != address(0), "StrategyRegistry: unknown strategy");

        require(adapter != address(0), "StrategyRegistry: adapter=0");
        require(dexRouter != address(0), "StrategyRegistry: dexRouter=0");
        require(
            token0 != address(0) && token1 != address(0),
            "StrategyRegistry: tokens=0"
        );

        s.adapter = adapter;
        s.dexRouter = dexRouter;
        s.token0 = token0;
        s.token1 = token1;
        s.name = name;
        s.description = description;

        emit StrategyUpdated(
            strategyId,
            adapter,
            dexRouter,
            token0,
            token1,
            name
        );
    }

    /**
     * @notice Activate or deactivate a given strategy.
     * @param strategyId Strategy id to update.
     * @param active New active flag.
     */
    function setStrategyActive(
        uint256 strategyId,
        bool active
    ) external onlyOwner {
        Strategy storage s = _strategies[strategyId];
        require(s.adapter != address(0), "StrategyRegistry: unknown strategy");

        s.active = active;
        emit StrategyStatusChanged(strategyId, active);
    }
}
