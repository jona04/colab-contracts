// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "./ClientVault.sol";
import "./StrategyRegistry.sol";

/**
 * @title VaultFactory
 * @notice Factory responsible for deploying ClientVault instances linked to user-owned strategies.
 * @dev
 * - Enforces that the strategy is owned by the vault owner (strategyOwner == vaultOwner).
 * - Requires the strategy to exist and be active under that owner in StrategyRegistry.
 * - Keeps indexing of created vaults:
 *     * by global index,
 *     * by owner,
 *     * by (owner, strategyId).
 */
contract VaultFactory is Ownable, ReentrancyGuard {
    address public executor;
    StrategyRegistry public immutable strategyRegistry;
    address public feeCollector;

    uint32 public defaultCooldownSec;
    uint16 public defaultMaxSlippageBps;
    bool public defaultAllowSwap;

    struct VaultInfo {
        address vault;
        address owner;
        uint256 strategyId; // per-owner strategy id
    }

    /// @notice Array of all ClientVaults created by this factory.
    VaultInfo[] public allVaults;

    /// @notice Mapping of owner => list of vault addresses.
    mapping(address => address[]) public vaultsByOwner;

    /// @notice Mapping (owner => strategyId => vault addresses).
    mapping(address => mapping(uint256 => address[]))
        public vaultsByOwnerStrategy;

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    /// @notice Emitted when the executor address is updated.
    event ExecutorUpdated(
        address indexed oldExecutor,
        address indexed newExecutor
    );

    /// @notice Emitted when the feeCollector is updated.
    event FeeCollectorUpdated(
        address indexed oldCollector,
        address indexed newCollector
    );

    /// @notice Emitted when default automation config is updated.
    event DefaultsUpdated(
        uint32 cooldownSec,
        uint16 maxSlippageBps,
        bool allowSwap
    );

    /// @notice Emitted when a new ClientVault is deployed.
    event ClientVaultDeployed(
        address indexed vault,
        address indexed owner,
        uint256 indexed strategyId,
        uint256 vaultIndex
    );

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    /**
     * @notice Construct a new VaultFactory.
     * @param initialOwner Owner of the factory (protocol multisig).
     * @param _strategyRegistry Address of the StrategyRegistry contract.
     * @param _executor Global automation executor address (Colab bot).
     * @param _feeCollector Protocol fee collector (may be zero if not yet used).
     * @param _defaultCooldownSec Default automation cooldown (seconds).
     * @param _defaultMaxSlippageBps Default max slippage (basis points).
     * @param _defaultAllowSwap Default flag for allowing swap in automation.
     */
    constructor(
        address initialOwner,
        address _strategyRegistry,
        address _executor,
        address _feeCollector,
        uint32 _defaultCooldownSec,
        uint16 _defaultMaxSlippageBps,
        bool _defaultAllowSwap
    ) Ownable(initialOwner) {
        require(_strategyRegistry != address(0), "VaultFactory: registry=0");
        require(_executor != address(0), "VaultFactory: executor=0");

        strategyRegistry = StrategyRegistry(_strategyRegistry);
        executor = _executor;
        feeCollector = _feeCollector;

        defaultCooldownSec = _defaultCooldownSec;
        defaultMaxSlippageBps = _defaultMaxSlippageBps;
        defaultAllowSwap = _defaultAllowSwap;
    }

    // -------------------------------------------------------------------------
    // Owner-only configuration
    // -------------------------------------------------------------------------

    /**
     * @notice Update the global automation executor address.
     * @param newExecutor New executor (Colab bot) address.
     */
    function setExecutor(address newExecutor) external onlyOwner {
        require(newExecutor != address(0), "VaultFactory: executor=0");
        address old = executor;
        executor = newExecutor;
        emit ExecutorUpdated(old, newExecutor);
    }

    /**
     * @notice Update the protocol fee collector address.
     * @param newCollector New fee collector address (can be zero to effectively disable fees).
     */
    function setFeeCollector(address newCollector) external onlyOwner {
        address old = feeCollector;
        feeCollector = newCollector;
        emit FeeCollectorUpdated(old, newCollector);
    }

    /**
     * @notice Update default automation parameters used by newly created ClientVaults.
     * @param _cooldownSec New default cooldown in seconds.
     * @param _maxSlippageBps New default max slippage in basis points.
     * @param _allowSwap New default flag for allowing swaps.
     */
    function setDefaults(
        uint32 _cooldownSec,
        uint16 _maxSlippageBps,
        bool _allowSwap
    ) external onlyOwner {
        defaultCooldownSec = _cooldownSec;
        defaultMaxSlippageBps = _maxSlippageBps;
        defaultAllowSwap = _allowSwap;
        emit DefaultsUpdated(_cooldownSec, _maxSlippageBps, _allowSwap);
    }

    // -------------------------------------------------------------------------
    // Views
    // -------------------------------------------------------------------------

    /**
     * @notice Returns the number of ClientVaults deployed by this factory.
     * @return length Number of vaults.
     */
    function allVaultsLength() external view returns (uint256 length) {
        return allVaults.length;
    }

    /**
     * @notice Returns all vaults created for a given owner.
     * @param owner Address of the vault owner.
     * @return vaults Array of vault addresses.
     */
    function getVaultsByOwner(
        address owner
    ) external view returns (address[] memory vaults) {
        return vaultsByOwner[owner];
    }

    /**
     * @notice Returns all vaults using a given owner and strategyId.
     * @param strategyId Strategy id.
     * @return vaults Array of vault addresses.
     */
    function getVaultsByOwnerAndStrategy(
        address owner,
        uint256 strategyId
    ) external view returns (address[] memory vaults) {
        return vaultsByOwnerStrategy[owner][strategyId];
    }

    // -------------------------------------------------------------------------
    // Vault deployment
    // -------------------------------------------------------------------------

    /**
     * @notice Create a new ClientVault linked to a user-owned strategy.
     * @dev
     * - Resolves the vault owner from ownerOverride or msg.sender.
     * - Fetches the strategy under (vaultOwner, strategyId) and requires it to be active.
     * - Deploys a new ClientVault with adapter/router from that strategy.
     * @param strategyId Per-owner strategy id (scoped to the vault owner).
     * @param ownerOverride Optional explicit owner address; if zero, defaults to msg.sender.
     * @return vaultAddr Address of the newly created ClientVault.
     */
    function createClientVault(
        uint256 strategyId,
        address ownerOverride
    ) external nonReentrant returns (address vaultAddr) {
        address vaultOwner = (ownerOverride != address(0))
            ? ownerOverride
            : msg.sender;
        require(vaultOwner != address(0), "VaultFactory: owner=0");

        StrategyRegistry.Strategy memory strat = strategyRegistry.getStrategy(
            vaultOwner,
            strategyId
        );
        require(strat.active, "VaultFactory: strategy not active");

        ClientVault vault = new ClientVault(
            vaultOwner,
            executor,
            strat.adapter,
            strat.dexRouter,
            feeCollector,
            strategyId,
            defaultCooldownSec,
            defaultMaxSlippageBps,
            defaultAllowSwap
        );

        vaultAddr = address(vault);

        uint256 idx = allVaults.length;
        allVaults.push(
            VaultInfo({
                vault: vaultAddr,
                owner: vaultOwner,
                strategyId: strategyId
            })
        );

        vaultsByOwner[vaultOwner].push(vaultAddr);
        vaultsByOwnerStrategy[vaultOwner][strategyId].push(vaultAddr);

        emit ClientVaultDeployed(vaultAddr, vaultOwner, strategyId, idx);
    }
}
