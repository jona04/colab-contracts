// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import {ProtocolFeeCollector} from "../../src/core/ProtocolFeeCollector.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";

/**
 * @title ProtocolFeeCollectorTest
 * @notice Unit tests for ProtocolFeeCollector.
 */
contract ProtocolFeeCollectorTest is Test {
    ProtocolFeeCollector internal collector;
    MockERC20 internal token;

    address internal owner = address(0xA0FFEE);
    address internal treasury = address(0xB0FFEE);
    address internal reporter = address(0xC0FFEE);
    address internal other = address(0xD0FFEE);

    uint16 internal initialBps = 1000; // 10%

    function setUp() public {
        vm.prank(owner);
        collector = new ProtocolFeeCollector(owner, treasury, initialBps);

        token = new MockERC20("Mock Token", "MTK");
        token.mint(reporter, 1_000e18);
    }

    // -------------------------------------------------------------------------
    // Constructor & config
    // -------------------------------------------------------------------------

    function testInitialConfigIsCorrect() public {
        assertEq(
            collector.treasury(),
            treasury,
            "Treasury should match constructor"
        );
        assertEq(
            collector.protocolFeeBps(),
            initialBps,
            "Initial protocol fee BPS should match constructor"
        );
        assertEq(collector.owner(), owner, "Owner should match constructor");
    }

    function testSetTreasuryOnlyOwner() public {
        address newTreasury = address(0xCAFE);

        // Non-owner must revert with OwnableUnauthorizedAccount
        vm.prank(other);
        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                other
            )
        );
        collector.setTreasury(newTreasury);

        // Owner can update
        vm.prank(owner);
        collector.setTreasury(newTreasury);
        assertEq(
            collector.treasury(),
            newTreasury,
            "Treasury should be updated by owner"
        );
    }

    function testSetTreasuryZeroAddressReverts() public {
        vm.prank(owner);
        vm.expectRevert("ProtocolFeeCollector: treasury=0");
        collector.setTreasury(address(0));
    }

    function testSetProtocolFeeBpsOnlyOwner() public {
        uint16 newBps = 1500;

        vm.prank(other);
        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                other
            )
        );
        collector.setProtocolFeeBps(newBps);

        vm.prank(owner);
        collector.setProtocolFeeBps(newBps);
        assertEq(
            collector.protocolFeeBps(),
            newBps,
            "Protocol fee BPS should be updated"
        );
    }

    function testSetProtocolFeeBpsTooHighReverts() public {
        uint16 tooHigh = 6000; // > 5000 (50%)

        vm.prank(owner);
        vm.expectRevert("ProtocolFeeCollector: fee too high");
        collector.setProtocolFeeBps(tooHigh);
    }

    function testSetReporterOnlyOwner() public {
        // non-owner cannot authorize
        vm.prank(other);
        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                other
            )
        );
        collector.setReporter(reporter, true);

        // owner authorizes
        vm.prank(owner);
        collector.setReporter(reporter, true);
        assertTrue(
            collector.authorizedReporter(reporter),
            "Reporter should be authorized by owner"
        );
    }

    function testSetReporterZeroAddressReverts() public {
        vm.prank(owner);
        vm.expectRevert("ProtocolFeeCollector: reporter=0");
        collector.setReporter(address(0), true);
    }

    // -------------------------------------------------------------------------
    // Reporting & Withdrawals
    // -------------------------------------------------------------------------

    function _authorizeReporter() internal {
        vm.prank(owner);
        collector.setReporter(reporter, true);
    }

    function testReportFeesSuccess() public {
        _authorizeReporter();

        uint256 amount = 100e18;
        uint256 strategyId = 42;

        // Reporter must approve the collector to pull tokens
        vm.startPrank(reporter);
        token.approve(address(collector), amount);
        collector.reportFees(strategyId, address(token), amount);
        vm.stopPrank();

        // Collector should hold the tokens
        assertEq(
            token.balanceOf(address(collector)),
            amount,
            "Collector should hold reported tokens"
        );

        // Totals should be updated
        assertEq(
            collector.totalByToken(address(token)),
            amount,
            "totalByToken should track the reported amount"
        );
        assertEq(
            collector.strategyByToken(strategyId, address(token)),
            amount,
            "strategyByToken should track the reported amount for the strategy"
        );
    }

    function testReportFeesRequiresAuthorizedReporter() public {
        uint256 amount = 50e18;
        uint256 strategyId = 1;

        vm.startPrank(reporter);
        token.approve(address(collector), amount);
        vm.expectRevert("ProtocolFeeCollector: not authorized");
        collector.reportFees(strategyId, address(token), amount);
        vm.stopPrank();
    }

    function testReportFeesZeroTokenReverts() public {
        _authorizeReporter();
        uint256 amount = 10e18;

        vm.startPrank(reporter);
        vm.expectRevert("ProtocolFeeCollector: token=0");
        collector.reportFees(1, address(0), amount);
        vm.stopPrank();
    }

    function testReportFeesZeroAmountReverts() public {
        _authorizeReporter();

        vm.startPrank(reporter);
        vm.expectRevert("ProtocolFeeCollector: amount=0");
        collector.reportFees(1, address(token), 0);
        vm.stopPrank();
    }

    function testWithdrawFeesToTreasuryByDefault() public {
        _authorizeReporter();

        uint256 amount = 100e18;
        uint256 strategyId = 7;

        // Report some fees first
        vm.startPrank(reporter);
        token.approve(address(collector), amount);
        collector.reportFees(strategyId, address(token), amount);
        vm.stopPrank();

        uint256 prevTreasuryBal = token.balanceOf(treasury);

        // Only owner can withdraw
        vm.prank(other);
        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                other
            )
        );
        collector.withdrawFees(address(token), amount, address(0));

        vm.prank(owner);
        collector.withdrawFees(address(token), amount, address(0));

        assertEq(
            token.balanceOf(treasury),
            prevTreasuryBal + amount,
            "Treasury should receive withdrawn fees"
        );
        assertEq(
            token.balanceOf(address(collector)),
            0,
            "Collector balance should decrease after withdraw"
        );
    }

    function testWithdrawFeesToCustomRecipient() public {
        _authorizeReporter();

        uint256 amount = 60e18;
        uint256 strategyId = 5;

        token.mint(reporter, amount);
        vm.startPrank(reporter);
        token.approve(address(collector), amount);
        collector.reportFees(strategyId, address(token), amount);
        vm.stopPrank();

        address recipient = address(0xC0FFEE);
        uint256 prevRecipientBal = token.balanceOf(recipient);

        vm.prank(owner);
        collector.withdrawFees(address(token), amount, recipient);

        assertEq(
            token.balanceOf(recipient),
            prevRecipientBal + amount,
            "Custom recipient should receive withdrawn fees"
        );
    }

    function testWithdrawFeesRecipientZeroResolvesToTreasury() public {
        _authorizeReporter();

        uint256 amount = 20e18;
        uint256 strategyId = 9;

        vm.startPrank(reporter);
        token.approve(address(collector), amount);
        collector.reportFees(strategyId, address(token), amount);
        vm.stopPrank();

        vm.prank(owner);
        collector.withdrawFees(address(token), amount, address(0));

        assertEq(
            token.balanceOf(treasury),
            amount,
            "Zero recipient should default to treasury"
        );
    }

    function testWithdrawFeesZeroTokenReverts() public {
        vm.prank(owner);
        vm.expectRevert("ProtocolFeeCollector: token=0");
        collector.withdrawFees(address(0), 1e18, address(0x1));
    }
}
