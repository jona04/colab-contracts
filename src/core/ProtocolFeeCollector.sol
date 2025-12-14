// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title ProtocolFeeCollector
 * @notice Central collector for protocol-level performance fees.
 * @dev
 * - This contract is agnostic to the underlying strategy logic.
 * - Authorized reporters (e.g., ClientVaults or adapters) call `reportFees`,
 *   transferring the protocol's share of fees into this contract.
 * - The owner (Colab) can withdraw accumulated tokens to a treasury address.
 * - For simplicity, there is no fee share for strategy owners at this stage:
 *   100% of the reported fee amount is protocol revenue.
 */
contract ProtocolFeeCollector is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice Address that ultimately receives withdrawn protocol fees (e.g. multisig).
    address public treasury;

    /// @notice Protocol fee rate in basis points (e.g. 1000 = 10%).
    /// @dev This is used off-chain to compute grossAmount; here we only accept
    ///      the already computed protocol share. Still, we keep it for visibility.
    uint16 public protocolFeeBps;

    /// @notice Addresses allowed to call `reportFees`.
    mapping(address => bool) public authorizedReporter;

    /// @notice Total fees accrued per token for the entire protocol.
    mapping(address => uint256) public totalByToken;

    /// @notice Fees accrued per strategy id and token.
    mapping(uint256 => mapping(address => uint256)) public strategyByToken;

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    /// @notice Emitted when the treasury address is updated.
    event TreasuryUpdated(
        address indexed oldTreasury,
        address indexed newTreasury
    );

    /// @notice Emitted when the protocol fee rate is updated.
    event ProtocolFeeBpsUpdated(uint16 oldBps, uint16 newBps);

    /// @notice Emitted when an address is (un)authorized as fee reporter.
    event ReporterAuthorizationUpdated(
        address indexed reporter,
        bool authorized
    );

    /// @notice Emitted when fees are reported by an authorized reporter.
    event FeesReported(
        address indexed reporter,
        uint256 indexed strategyId,
        address indexed token,
        uint256 amount
    );

    /// @notice Emitted when fees are withdrawn to the treasury or another address.
    event FeesWithdrawn(
        address indexed token,
        address indexed to,
        uint256 amount
    );

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    /**
     * @notice Construct a new ProtocolFeeCollector.
     * @param initialOwner Owner of this contract (typically a protocol multisig).
     * @param initialTreasury Address where fees will ultimately be withdrawn.
     * @param initialProtocolFeeBps Initial protocol fee in basis points (for reference).
     */
    constructor(
        address initialOwner,
        address initialTreasury,
        uint16 initialProtocolFeeBps
    ) Ownable(initialOwner) {
        require(
            initialTreasury != address(0),
            "ProtocolFeeCollector: treasury=0"
        );
        require(
            initialProtocolFeeBps <= 5000,
            "ProtocolFeeCollector: fee too high"
        ); // max 50%

        treasury = initialTreasury;
        protocolFeeBps = initialProtocolFeeBps;
    }

    // -------------------------------------------------------------------------
    // Owner-only configuration
    // -------------------------------------------------------------------------

    /**
     * @notice Update the protocol treasury address.
     * @param newTreasury New treasury address.
     */
    function setTreasury(address newTreasury) external onlyOwner {
        require(newTreasury != address(0), "ProtocolFeeCollector: treasury=0");
        address old = treasury;
        treasury = newTreasury;
        emit TreasuryUpdated(old, newTreasury);
    }

    /**
     * @notice Update the reference protocol fee rate (bps).
     * @dev This is informational only unless used off-chain to compute gross fees.
     * @param newBps New fee rate in basis points.
     */
    function setProtocolFeeBps(uint16 newBps) external onlyOwner {
        require(newBps <= 5000, "ProtocolFeeCollector: fee too high"); // safety upper bound
        uint16 old = protocolFeeBps;
        protocolFeeBps = newBps;
        emit ProtocolFeeBpsUpdated(old, newBps);
    }

    /**
     * @notice Authorize or revoke an address as fee reporter.
     * @dev Typical reporters: ClientVaults, adapters, or a vault manager contract.
     * @param reporter Address to update.
     * @param authorized True to authorize, false to revoke.
     */
    function setReporter(address reporter, bool authorized) external onlyOwner {
        require(reporter != address(0), "ProtocolFeeCollector: reporter=0");
        authorizedReporter[reporter] = authorized;
        emit ReporterAuthorizationUpdated(reporter, authorized);
    }

    // -------------------------------------------------------------------------
    // Fee reporting
    // -------------------------------------------------------------------------

    /**
     * @notice Report protocol fees for a given strategy and token.
     * @dev
     * - Caller must be an authorized reporter.
     * - `amount` is assumed to be the protocol's share already (not gross fees).
     * - The function pulls tokens from the reporter into this contract via ERC-20 transferFrom.
     * @param strategyId Strategy id this fee is associated with.
     * @param token ERC-20 token in which the fee is denominated.
     * @param amount Protocol fee amount (raw units) to be pulled from the reporter.
     */
    function reportFees(
        uint256 strategyId,
        address token,
        uint256 amount
    ) external nonReentrant {
        require(
            authorizedReporter[msg.sender],
            "ProtocolFeeCollector: not authorized"
        );
        require(token != address(0), "ProtocolFeeCollector: token=0");
        require(amount > 0, "ProtocolFeeCollector: amount=0");

        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        totalByToken[token] += amount;
        strategyByToken[strategyId][token] += amount;

        emit FeesReported(msg.sender, strategyId, token, amount);
    }

    // -------------------------------------------------------------------------
    // Withdrawals
    // -------------------------------------------------------------------------

    /**
     * @notice Withdraw accumulated fees for a given token.
     * @dev Only owner can withdraw. Default recipient is the treasury.
     * @param token ERC-20 token to withdraw.
     * @param amount Amount to withdraw (raw units).
     * @param to Recipient address; if zero, defaults to `treasury`.
     */
    function withdrawFees(
        address token,
        uint256 amount,
        address to
    ) external onlyOwner nonReentrant {
        require(token != address(0), "ProtocolFeeCollector: token=0");
        address recipient = (to == address(0)) ? treasury : to;
        require(recipient != address(0), "ProtocolFeeCollector: recipient=0");

        IERC20(token).safeTransfer(recipient, amount);
        emit FeesWithdrawn(token, recipient, amount);
    }
}
