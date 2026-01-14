// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";

/**
 * @title StrategyRegistry
 * @notice Per-user registry of strategies that can be used by ClientVaults.
 * @dev
 * - The protocol owner maintains allowlists for adapters and routers.
 * - Each user registers and manages their own strategies, indexed by (owner, strategyId).
 * - Strategy ownership is enforced by VaultFactory: the strategy owner must match the vault owner.
 */
contract StrategyRegistry is Ownable {
    /// @notice Metadata describing a single strategy.
    struct Strategy {
        address adapter;
        address dexRouter;
        address token0;
        address token1;
        string name;
        string description;
        bool active;
    }

    // -------------------------------------------------------------------------
    // Allowlists (protocol-level safety)
    // -------------------------------------------------------------------------

    /// @notice Approved adapter contracts that users can reference.
    mapping(address => bool) public allowedAdapters;

    /// @notice Approved DEX routers that users can reference.
    mapping(address => bool) public allowedRouters;

    // -------------------------------------------------------------------------
    // Per-user storage
    // -------------------------------------------------------------------------

    /// @notice Next strategy id to be assigned per owner (starts at 1).
    mapping(address => uint256) public nextStrategyIdByOwner;

    /// @notice Mapping (owner => strategyId => Strategy).
    mapping(address => mapping(uint256 => Strategy)) private _strategiesByOwner;

    /// @notice Owner => list of strategyIds (for enumeration).
    mapping(address => uint256[]) private _strategyIdsByOwner;

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    event AdapterAllowlistUpdated(address indexed adapter, bool allowed);
    event RouterAllowlistUpdated(address indexed router, bool allowed);

    event StrategyRegistered(
        address indexed owner,
        uint256 indexed strategyId,
        address indexed adapter,
        address dexRouter,
        address token0,
        address token1,
        string name
    );

    event StrategyUpdated(
        address indexed owner,
        uint256 indexed strategyId,
        address indexed adapter,
        address dexRouter,
        address token0,
        address token1,
        string name
    );

    event StrategyStatusChanged(
        address indexed owner,
        uint256 indexed strategyId,
        bool active
    );

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    /**
     * @notice Construct a new StrategyRegistry.
     * @param initialOwner Address that will control this registry (typically a multisig).
     */
    constructor(address initialOwner) Ownable(initialOwner) {}

    // -------------------------------------------------------------------------
    // Protocol owner-only allowlist management
    // -------------------------------------------------------------------------

    /**
     * @notice Allow or disallow a given adapter contract.
     * @param adapter Adapter address.
     * @param allowed True to allow, false to disallow.
     */
    function setAdapterAllowed(
        address adapter,
        bool allowed
    ) external onlyOwner {
        require(adapter != address(0), "StrategyRegistry: adapter=0");
        allowedAdapters[adapter] = allowed;
        emit AdapterAllowlistUpdated(adapter, allowed);
    }

    /**
     * @notice Allow or disallow a given router contract.
     * @param router Router address.
     * @param allowed True to allow, false to disallow.
     */
    function setRouterAllowed(address router, bool allowed) external onlyOwner {
        require(router != address(0), "StrategyRegistry: router=0");
        allowedRouters[router] = allowed;
        emit RouterAllowlistUpdated(router, allowed);
    }

    // -------------------------------------------------------------------------
    // Views
    // -------------------------------------------------------------------------

    /**
     * @notice Returns full metadata for a given owner's strategy id.
     * @param owner Owner of the strategy.
     * @param strategyId Id of the strategy to query (scoped to `owner`).
     * @return s Strategy struct.
     */
    function getStrategy(
        address owner,
        uint256 strategyId
    ) public view returns (Strategy memory s) {
        s = _strategiesByOwner[owner][strategyId];
        require(s.adapter != address(0), "StrategyRegistry: unknown strategy");
    }

    /**
     * @notice Returns full metadata for msg.sender's strategy id.
     * @param strategyId Id of the strategy (scoped to msg.sender).
     * @return s Strategy struct.
     */
    function getMyStrategy(
        uint256 strategyId
    ) external view returns (Strategy memory s) {
        return getStrategy(msg.sender, strategyId);
    }

    /**
     * @notice Returns the number of strategies registered by a given owner.
     * @param owner Owner address.
     * @return length Count of strategies.
     */
    function strategiesLengthByOwner(
        address owner
    ) external view returns (uint256 length) {
        return _strategyIdsByOwner[owner].length;
    }

    /**
     * @notice Returns the list of strategyIds registered by a given owner.
     * @param owner Owner address.
     * @return ids Array of ids.
     */
    function getStrategyIdsByOwner(
        address owner
    ) external view returns (uint256[] memory ids) {
        return _strategyIdsByOwner[owner];
    }

    /**
     * @notice Returns all strategies registered by a given owner.
     * @dev This is a view-only helper intended for off-chain indexing/UI.
     * @param owner Owner address.
     * @return all Array of Strategy structs.
     */
    function getAllStrategiesByOwner(
        address owner
    ) external view returns (Strategy[] memory all) {
        uint256[] memory ids = _strategyIdsByOwner[owner];
        all = new Strategy[](ids.length);
        for (uint256 i = 0; i < ids.length; i++) {
            all[i] = _strategiesByOwner[owner][ids[i]];
        }
    }

    /**
     * @notice Checks if a strategy exists and is active for a given owner.
     * @param owner Owner of the strategy.
     * @param strategyId Id of the strategy.
     * @return True if exists and active.
     */
    function isStrategyActive(
        address owner,
        uint256 strategyId
    ) external view returns (bool) {
        Strategy memory s = _strategiesByOwner[owner][strategyId];
        return s.adapter != address(0) && s.active;
    }

    // -------------------------------------------------------------------------
    // User mutators
    // -------------------------------------------------------------------------

    /**
     * @notice Register a new strategy for msg.sender.
     * @dev Requires protocol allowlists for adapter/router.
     * @param adapter CL adapter contract bound to the target pool/gauge.
     * @param dexRouter DEX router to be used by ClientVaults for swaps.
     * @param token0 Underlying token0 of the pool.
     * @param token1 Underlying token1 of the pool.
     * @param name Human-readable name.
     * @param description Free-form description (e.g., JSON URI, IPFS hash).
     * @return strategyId Newly created per-user strategy id.
     */
    function registerStrategy(
        address adapter,
        address dexRouter,
        address token0,
        address token1,
        string calldata name,
        string calldata description
    ) external returns (uint256 strategyId) {
        require(adapter != address(0), "StrategyRegistry: adapter=0");
        require(dexRouter != address(0), "StrategyRegistry: router=0");
        require(
            token0 != address(0) && token1 != address(0),
            "StrategyRegistry: tokens=0"
        );
        require(token0 != token1, "StrategyRegistry: identical tokens");

        require(
            allowedAdapters[adapter],
            "StrategyRegistry: adapter not allowed"
        );
        require(
            allowedRouters[dexRouter],
            "StrategyRegistry: router not allowed"
        );

        address owner = msg.sender;
        uint256 nextId = nextStrategyIdByOwner[owner];
        if (nextId == 0) {
            nextId = 1;
        }

        strategyId = nextId;
        nextStrategyIdByOwner[owner] = nextId + 1;

        _strategiesByOwner[owner][strategyId] = Strategy({
            adapter: adapter,
            dexRouter: dexRouter,
            token0: token0,
            token1: token1,
            name: name,
            description: description,
            active: true
        });

        _strategyIdsByOwner[owner].push(strategyId);

        emit StrategyRegistered(
            owner,
            strategyId,
            adapter,
            dexRouter,
            token0,
            token1,
            name
        );
    }

    /**
     * @notice Update metadata of an existing msg.sender strategy.
     * @dev Does not change the active flag.
     * @param strategyId Strategy id to be updated (scoped to msg.sender).
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
    ) external {
        address owner = msg.sender;
        Strategy storage s = _strategiesByOwner[owner][strategyId];
        require(s.adapter != address(0), "StrategyRegistry: unknown strategy");

        require(adapter != address(0), "StrategyRegistry: adapter=0");
        require(dexRouter != address(0), "StrategyRegistry: router=0");
        require(
            token0 != address(0) && token1 != address(0),
            "StrategyRegistry: tokens=0"
        );
        require(token0 != token1, "StrategyRegistry: identical tokens");

        require(
            allowedAdapters[adapter],
            "StrategyRegistry: adapter not allowed"
        );
        require(
            allowedRouters[dexRouter],
            "StrategyRegistry: router not allowed"
        );

        s.adapter = adapter;
        s.dexRouter = dexRouter;
        s.token0 = token0;
        s.token1 = token1;
        s.name = name;
        s.description = description;

        emit StrategyUpdated(
            owner,
            strategyId,
            adapter,
            dexRouter,
            token0,
            token1,
            name
        );
    }

    /**
     * @notice Activate or deactivate a msg.sender strategy.
     * @param strategyId Strategy id to update (scoped to msg.sender).
     * @param active New active flag.
     */
    function setStrategyActive(uint256 strategyId, bool active) external {
        address owner = msg.sender;
        Strategy storage s = _strategiesByOwner[owner][strategyId];
        require(s.adapter != address(0), "StrategyRegistry: unknown strategy");

        s.active = active;
        emit StrategyStatusChanged(owner, strategyId, active);
    }
}
