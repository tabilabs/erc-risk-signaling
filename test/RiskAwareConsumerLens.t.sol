// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {IRiskRegistry} from "../src/interfaces/IRiskRegistry.sol";
import {MockAdjudicator} from "../src/MockAdjudicator.sol";
import {MockExecutor} from "../src/MockExecutor.sol";
import {MockRiskRegistry} from "../src/MockRiskRegistry.sol";
import {MockUSDC} from "../src/MockUSDC.sol";
import {RiskAwareConsumerLens} from "../src/RiskAwareConsumerLens.sol";
import {RiskResponseCodes} from "../src/libraries/RiskResponseCodes.sol";
import {RiskStateLens} from "../src/RiskStateLens.sol";
import {SafeVault4626} from "../src/SafeVault4626.sol";

contract MockResponderMismatch {
    bool internal emergencyActive;
    bytes32 internal currentReportId;
    bytes32[] internal restrictionIds;

    function setState(bool emergencyActive_, bytes32 reportId_, bytes32[] memory restrictionIds_) external {
        emergencyActive = emergencyActive_;
        currentReportId = reportId_;

        delete restrictionIds;
        for (uint256 i = 0; i < restrictionIds_.length; ++i) {
            restrictionIds.push(restrictionIds_[i]);
        }
    }

    function emergencyStatus() external view returns (bool, bytes32) {
        return (emergencyActive, currentReportId);
    }

    function getActiveRestrictions() external view returns (bytes32[] memory) {
        bytes32[] memory result = new bytes32[](restrictionIds.length);
        for (uint256 i = 0; i < restrictionIds.length; ++i) {
            result[i] = restrictionIds[i];
        }
        return result;
    }
}

contract RiskAwareConsumerLensTest is Test {
    address internal admin = makeAddr("admin");
    address internal whitehat = makeAddr("whitehat");
    address internal user = makeAddr("user");

    MockUSDC internal asset;
    MockRiskRegistry internal registry;
    MockAdjudicator internal adjudicator;
    MockExecutor internal executor;
    SafeVault4626 internal vault;
    SafeVault4626 internal otherVault;
    RiskStateLens internal stateLens;
    RiskAwareConsumerLens internal consumerLens;
    MockResponderMismatch internal mismatchResponder;

    function setUp() public {
        asset = new MockUSDC();
        registry = new MockRiskRegistry(0.1 ether, admin);
        adjudicator = new MockAdjudicator(registry, admin);
        executor = new MockExecutor();
        vault = new SafeVault4626(asset, admin);
        otherVault = new SafeVault4626(asset, admin);
        stateLens = new RiskStateLens();
        consumerLens = new RiskAwareConsumerLens(stateLens);
        mismatchResponder = new MockResponderMismatch();

        vm.prank(admin);
        registry.transferOwnership(address(adjudicator));
        vm.prank(admin);
        vault.setTrustedRiskRegistry(address(registry));
        vm.prank(admin);
        otherVault.setTrustedRiskRegistry(address(registry));

        asset.mint(user, 1_000_000e6);
        vm.prank(user);
        asset.approve(address(vault), type(uint256).max);
        vm.prank(user);
        vault.deposit(100e6, user);
    }

    function testRiskAwareConsumerReturnsNormalDecisionBeforeAnySignal() public view {
        bytes32 reportId = keccak256("missing-report");

        RiskAwareConsumerLens.Decision memory decision =
            consumerLens.decision(address(registry), address(vault), reportId);

        assertEq(decision.reportId, reportId);
        assertFalse(decision.shouldBlockNewDeposit);
        assertTrue(decision.shouldAllowExit);
        assertFalse(decision.shouldWarn);
        assertFalse(decision.shouldSkipVault);
        assertFalse(decision.isExecutionConsistent);
        assertEq(decision.decisionLevel, consumerLens.LEVEL_NORMAL());
        assertEq(decision.reasonCode, consumerLens.REASON_NONE());
        assertEq(decision.restrictionIds.length, 0);
    }

    function testRiskAwareConsumerReturnsNormalDecisionForZeroReportId() public view {
        RiskAwareConsumerLens.Decision memory decision =
            consumerLens.decision(address(registry), address(vault), bytes32(0));

        assertEq(decision.reportId, bytes32(0));
        assertFalse(decision.shouldBlockNewDeposit);
        assertTrue(decision.shouldAllowExit);
        assertFalse(decision.shouldWarn);
        assertFalse(decision.shouldSkipVault);
        assertFalse(decision.isExecutionConsistent);
        assertEq(decision.decisionLevel, consumerLens.LEVEL_NORMAL());
        assertEq(decision.reasonCode, consumerLens.REASON_NONE());
        assertEq(decision.restrictionIds.length, 0);
    }

    function testRiskAwareConsumerTreatsUnderReviewAsObservableButNonBlocking() public {
        vm.deal(whitehat, 1 ether);

        vm.prank(whitehat);
        bytes32 reportId = registry.raiseSignal{value: 0.1 ether}(
            address(vault),
            RiskResponseCodes.TARGET_TYPE_VAULT,
            RiskResponseCodes.RISK_DEPEG,
            3,
            bytes32(0),
            abi.encodePacked("evidence:under-review")
        );

        vm.prank(address(adjudicator));
        registry.resolveSignal(
            reportId,
            IRiskRegistry.Status.UnderReview,
            IRiskRegistry.ResolutionMetadata({adjudicator: address(adjudicator), resolutionHash: keccak256("under-review")})
        );

        RiskAwareConsumerLens.Decision memory decision =
            consumerLens.decision(address(registry), address(vault), reportId);

        assertFalse(decision.shouldBlockNewDeposit);
        assertTrue(decision.shouldAllowExit);
        assertFalse(decision.shouldWarn);
        assertFalse(decision.shouldSkipVault);
        assertFalse(decision.isExecutionConsistent);
        assertEq(decision.decisionLevel, consumerLens.LEVEL_NORMAL());
        assertEq(decision.reasonCode, consumerLens.REASON_NONE());
        assertEq(decision.restrictionIds.length, 0);
    }

    function testRiskAwareConsumerDifferentiatesConfirmedExecutedAndRecovered() public {
        bytes32 reportId = _raiseAndConfirm(address(vault));

        RiskAwareConsumerLens.Decision memory confirmedDecision =
            consumerLens.decision(address(registry), address(vault), reportId);
        assertFalse(confirmedDecision.shouldBlockNewDeposit);
        assertTrue(confirmedDecision.shouldAllowExit);
        assertTrue(confirmedDecision.shouldWarn);
        assertFalse(confirmedDecision.shouldSkipVault);
        assertFalse(confirmedDecision.isExecutionConsistent);
        assertEq(confirmedDecision.decisionLevel, consumerLens.LEVEL_WARNING());
        assertEq(confirmedDecision.reasonCode, consumerLens.REASON_CONFIRMED_NOT_EXECUTED());
        assertEq(confirmedDecision.restrictionIds.length, 0);

        executor.trigger(address(vault), address(registry), reportId);

        RiskAwareConsumerLens.Decision memory executedDecision =
            consumerLens.decision(address(registry), address(vault), reportId);
        assertTrue(executedDecision.shouldBlockNewDeposit);
        assertTrue(executedDecision.shouldAllowExit);
        assertTrue(executedDecision.shouldWarn);
        assertTrue(executedDecision.shouldSkipVault);
        assertTrue(executedDecision.isExecutionConsistent);
        assertEq(executedDecision.decisionLevel, consumerLens.LEVEL_BLOCK_NEW_DEPOSIT());
        assertEq(executedDecision.reasonCode, consumerLens.REASON_PAUSE_DEPOSIT_ACTIVE());
        assertEq(executedDecision.restrictionIds.length, 1);
        assertEq(executedDecision.restrictionIds[0], RiskResponseCodes.RESTRICTION_PAUSE_DEPOSIT);

        vm.prank(admin);
        vault.resolveLocalEmergency("peg restored locally");

        RiskAwareConsumerLens.Decision memory recoveredDecision =
            consumerLens.decision(address(registry), address(vault), reportId);
        assertFalse(recoveredDecision.shouldBlockNewDeposit);
        assertTrue(recoveredDecision.shouldAllowExit);
        assertTrue(recoveredDecision.shouldWarn);
        assertFalse(recoveredDecision.shouldSkipVault);
        assertFalse(recoveredDecision.isExecutionConsistent);
        assertEq(recoveredDecision.decisionLevel, consumerLens.LEVEL_RECOVERED_HISTORY());
        assertEq(recoveredDecision.reasonCode, consumerLens.REASON_LOCAL_RECOVERY_WITH_HISTORY());
        assertEq(recoveredDecision.restrictionIds.length, 0);
    }

    function testRiskAwareConsumerIgnoresReportBoundToDifferentVault() public {
        bytes32 reportId = _raiseAndConfirm(address(otherVault));

        RiskAwareConsumerLens.Decision memory decision =
            consumerLens.decision(address(registry), address(vault), reportId);

        assertEq(decision.reportId, reportId);
        assertFalse(decision.shouldBlockNewDeposit);
        assertTrue(decision.shouldAllowExit);
        assertFalse(decision.shouldWarn);
        assertFalse(decision.shouldSkipVault);
        assertFalse(decision.isExecutionConsistent);
        assertEq(decision.decisionLevel, consumerLens.LEVEL_NORMAL());
        assertEq(decision.reasonCode, consumerLens.REASON_NONE());
        assertEq(decision.restrictionIds.length, 0);
    }

    function testRiskAwareConsumerFlagsExecutedMismatchWithoutPretendingRecovery() public {
        bytes32 reportId = _raiseAndConfirm(address(mismatchResponder));

        vm.prank(address(mismatchResponder));
        registry.recordExecution(
            reportId,
            address(executor),
            RiskResponseCodes.ACTION_PAUSE_DEPOSIT,
            RiskResponseCodes.RESTRICTION_PAUSE_DEPOSIT,
            keccak256("executed:mismatch")
        );

        bytes32[] memory activeRestrictions = new bytes32[](1);
        activeRestrictions[0] = RiskResponseCodes.RESTRICTION_PAUSE_DEPOSIT;
        mismatchResponder.setState(false, bytes32(uint256(999)), activeRestrictions);

        RiskAwareConsumerLens.Decision memory decision =
            consumerLens.decision(address(registry), address(mismatchResponder), reportId);

        assertFalse(decision.shouldBlockNewDeposit);
        assertTrue(decision.shouldAllowExit);
        assertTrue(decision.shouldWarn);
        assertFalse(decision.shouldSkipVault);
        assertFalse(decision.isExecutionConsistent);
        assertEq(decision.decisionLevel, consumerLens.LEVEL_WARNING());
        assertEq(decision.reasonCode, consumerLens.REASON_EXECUTED_STATE_MISMATCH());
        assertEq(decision.restrictionIds.length, 1);
        assertEq(decision.restrictionIds[0], RiskResponseCodes.RESTRICTION_PAUSE_DEPOSIT);
    }

    function testRiskAwareConsumerTreatsUntrustedRegistryAsConfirmedNotExecuted() public {
        MockRiskRegistry rogueRegistry = new MockRiskRegistry(0.1 ether, admin);
        vm.deal(whitehat, 1 ether);

        vm.prank(whitehat);
        bytes32 rogueReportId = rogueRegistry.raiseSignal{value: 0.1 ether}(
            address(vault),
            RiskResponseCodes.TARGET_TYPE_VAULT,
            RiskResponseCodes.RISK_DEPEG,
            3,
            bytes32(0),
            abi.encodePacked("evidence:rogue-registry")
        );

        vm.prank(admin);
        rogueRegistry.resolveSignal(
            rogueReportId,
            IRiskRegistry.Status.Confirmed,
            IRiskRegistry.ResolutionMetadata({adjudicator: admin, resolutionHash: keccak256("rogue-confirmed")})
        );

        RiskAwareConsumerLens.Decision memory decision =
            consumerLens.decision(address(rogueRegistry), address(vault), rogueReportId);

        assertFalse(decision.shouldBlockNewDeposit);
        assertTrue(decision.shouldAllowExit);
        assertTrue(decision.shouldWarn);
        assertFalse(decision.shouldSkipVault);
        assertFalse(decision.isExecutionConsistent);
        assertEq(decision.decisionLevel, consumerLens.LEVEL_WARNING());
        assertEq(decision.reasonCode, consumerLens.REASON_CONFIRMED_NOT_EXECUTED());
        assertEq(decision.restrictionIds.length, 0);
    }

    function _raiseAndConfirm(address target) internal returns (bytes32 reportId) {
        vm.deal(whitehat, 1 ether);

        vm.prank(whitehat);
        reportId = registry.raiseSignal{value: 0.1 ether}(
            target,
            RiskResponseCodes.TARGET_TYPE_VAULT,
            RiskResponseCodes.RISK_DEPEG,
            3,
            bytes32(0),
            abi.encodePacked("evidence:slow-depeg")
        );

        vm.prank(admin);
        adjudicator.confirm(reportId, keccak256("confirmed:slow-depeg"));
    }
}
