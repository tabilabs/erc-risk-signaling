// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {Test} from "forge-std/Test.sol";

import {IRiskRegistry} from "../src/interfaces/IRiskRegistry.sol";
import {IProtocolResponder} from "../src/interfaces/IProtocolResponder.sol";
import {MockAdjudicator} from "../src/MockAdjudicator.sol";
import {MockExecutor} from "../src/MockExecutor.sol";
import {MockRiskRegistry} from "../src/MockRiskRegistry.sol";
import {MockUSDC} from "../src/MockUSDC.sol";
import {SafeVault4626} from "../src/SafeVault4626.sol";
import {RiskResponseCodes} from "../src/libraries/RiskResponseCodes.sol";

contract RiskResponseFlowTest is Test {
    event SignalResolved(
        bytes32 indexed reportId,
        address indexed target,
        IRiskRegistry.Status indexed status,
        address adjudicator,
        bytes32 resolutionHash
    );
    event SignalExecutionRecorded(
        bytes32 indexed reportId,
        address indexed target,
        address indexed executor,
        bytes32 actionId,
        bytes32 restrictionId,
        bytes32 resultHash
    );
    event ExecutionTriggered(
        address indexed responder, address indexed registry, bytes32 indexed reportId, address caller
    );
    event EmergencyActionExecuted(
        bytes32 indexed reportId,
        address indexed registry,
        address indexed executor,
        bytes32 actionId,
        bytes32 restrictionId,
        bytes32 resultHash
    );
    event LocalEmergencyResolved(
        address indexed resolvedBy,
        bytes32 indexed previousReportId,
        bytes32 indexed clearedRestrictionId,
        string reason
    );
    event TrustedRiskRegistryUpdated(
        address indexed updatedBy, address indexed previousRegistry, address indexed newRegistry
    );

    address internal admin = makeAddr("admin");
    address internal whitehat = makeAddr("whitehat");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    MockUSDC internal asset;
    MockRiskRegistry internal registry;
    MockAdjudicator internal adjudicator;
    MockExecutor internal executor;
    SafeVault4626 internal vault;
    SafeVault4626 internal otherVault;

    function setUp() public {
        asset = new MockUSDC();
        registry = new MockRiskRegistry(0.1 ether, admin);
        adjudicator = new MockAdjudicator(registry, admin);
        executor = new MockExecutor();
        vault = new SafeVault4626(asset, admin);
        otherVault = new SafeVault4626(asset, admin);

        vm.prank(admin);
        registry.transferOwnership(address(adjudicator));
        vm.prank(admin);
        vault.setTrustedRiskRegistry(address(registry));
        vm.prank(admin);
        otherVault.setTrustedRiskRegistry(address(registry));

        asset.mint(alice, 1_000_000e6);
        asset.mint(bob, 1_000_000e6);

        vm.prank(alice);
        asset.approve(address(vault), type(uint256).max);
        vm.prank(bob);
        asset.approve(address(vault), type(uint256).max);
    }

    function testConfirmedSignalPausesDepositButKeepsWithdrawOpen() public {
        vm.prank(alice);
        vault.deposit(100e6, alice);

        bytes32 reportId = _raiseAndConfirm(address(vault));

        (bool emergencyActiveBeforeTrigger, bytes32 activeReportBeforeTrigger) = vault.emergencyStatus();
        assertFalse(emergencyActiveBeforeTrigger);
        assertEq(activeReportBeforeTrigger, bytes32(0));
        assertEq(vault.maxDeposit(bob), type(uint256).max);

        bytes32 resultHash = _executionSnapshotHash(reportId);
        vm.expectEmit(address(registry));
        emit SignalExecutionRecorded(
            reportId,
            address(vault),
            address(executor),
            RiskResponseCodes.ACTION_PAUSE_DEPOSIT,
            RiskResponseCodes.RESTRICTION_PAUSE_DEPOSIT,
            resultHash
        );
        vm.expectEmit(address(vault));
        emit EmergencyActionExecuted(
            reportId,
            address(registry),
            address(executor),
            RiskResponseCodes.ACTION_PAUSE_DEPOSIT,
            RiskResponseCodes.RESTRICTION_PAUSE_DEPOSIT,
            resultHash
        );
        vm.expectEmit(address(executor));
        emit ExecutionTriggered(address(vault), address(registry), reportId, address(this));
        executor.trigger(address(vault), address(registry), reportId);

        (bool emergencyActiveAfterTrigger, bytes32 activeReportAfterTrigger) = vault.emergencyStatus();
        bytes32[] memory restrictions = vault.getActiveRestrictions();
        IRiskRegistry.Signal memory executedSignal = registry.getSignal(reportId);
        IRiskRegistry.ExecutionRecord memory executionRecord = registry.getExecution(reportId);
        assertTrue(emergencyActiveAfterTrigger);
        assertEq(activeReportAfterTrigger, reportId);
        assertEq(uint256(executedSignal.status), uint256(IRiskRegistry.Status.Confirmed));
        assertTrue(executionRecord.recorded);
        assertEq(executionRecord.executor, address(executor));
        assertEq(restrictions.length, 1);
        assertEq(restrictions[0], RiskResponseCodes.RESTRICTION_PAUSE_DEPOSIT);
        assertEq(vault.maxDeposit(bob), 0);
        assertGt(vault.maxWithdraw(alice), 0);
        assertTrue(vault.supportsInterface(type(IProtocolResponder).interfaceId));
        assertTrue(vault.supportsInterface(type(IERC165).interfaceId));
        bytes32[] memory supportedActions = vault.getSupportedActions();
        assertEq(supportedActions.length, 1);
        assertEq(supportedActions[0], RiskResponseCodes.ACTION_PAUSE_DEPOSIT);

        vm.prank(bob);
        vm.expectRevert();
        vault.deposit(10e6, bob);

        vm.prank(alice);
        vault.withdraw(40e6, alice, alice);

        assertEq(asset.balanceOf(alice), 1_000_000e6 - 100e6 + 40e6);
        assertEq(asset.balanceOf(address(vault)), 60e6);
    }

    function testTrustedRiskRegistryIsReadableAndRejectsUntrustedRegistry() public {
        MockRiskRegistry rogueRegistry = new MockRiskRegistry(0.1 ether, admin);
        assertEq(vault.trustedRiskRegistry(), address(registry));

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

        vm.expectRevert(
            abi.encodeWithSelector(SafeVault4626.UntrustedRegistry.selector, address(rogueRegistry), address(registry))
        );
        executor.trigger(address(vault), address(rogueRegistry), rogueReportId);

        (bool emergencyActive, bytes32 activeReportId) = vault.emergencyStatus();
        assertFalse(emergencyActive);
        assertEq(activeReportId, bytes32(0));
        assertEq(vault.maxDeposit(alice), type(uint256).max);
    }

    function testProcessedReportBlocksReplayAfterLocalRecovery() public {
        bytes32 reportId = _raiseAndConfirm(address(vault));

        executor.trigger(address(vault), address(registry), reportId);
        assertTrue(vault.processedReports(reportId));

        vm.expectEmit(address(vault));
        emit LocalEmergencyResolved(admin, reportId, RiskResponseCodes.RESTRICTION_PAUSE_DEPOSIT, "usdc repeg");
        vm.prank(admin);
        vault.resolveLocalEmergency("usdc repeg");

        (bool emergencyActiveAfterResolve, bytes32 activeReportAfterResolve) = vault.emergencyStatus();
        assertFalse(emergencyActiveAfterResolve);
        assertEq(activeReportAfterResolve, bytes32(0));
        assertEq(vault.maxDeposit(alice), type(uint256).max);
        assertEq(vault.activeReportId(), bytes32(0));

        vm.expectRevert(abi.encodeWithSelector(SafeVault4626.ReportAlreadyProcessed.selector, reportId));
        executor.trigger(address(vault), address(registry), reportId);
    }

    function testRaiseSignalRevertsWhenBondBelowFloor() public {
        vm.deal(whitehat, 1 ether);

        vm.prank(whitehat);
        vm.expectRevert(abi.encodeWithSelector(MockRiskRegistry.BondTooLow.selector, 0.05 ether, registry.BOND_FLOOR()));
        registry.raiseSignal{value: 0.05 ether}(
            address(vault),
            RiskResponseCodes.TARGET_TYPE_VAULT,
            RiskResponseCodes.RISK_DEPEG,
            3,
            bytes32(0),
            abi.encodePacked("evidence:too-cheap")
        );
    }

    function testResolveSignalRevertsOnInvalidFinalStatus() public {
        MockRiskRegistry directRegistry = new MockRiskRegistry(0.1 ether, admin);
        vm.deal(whitehat, 1 ether);

        vm.prank(whitehat);
        bytes32 reportId = directRegistry.raiseSignal{value: 0.1 ether}(
            address(vault),
            RiskResponseCodes.TARGET_TYPE_VAULT,
            RiskResponseCodes.RISK_DEPEG,
            3,
            bytes32(0),
            abi.encodePacked("evidence:invalid-status")
        );

        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(MockRiskRegistry.InvalidFinalStatus.selector, IRiskRegistry.Status.None)
        );
        directRegistry.resolveSignal(
            reportId,
            IRiskRegistry.Status.None,
            IRiskRegistry.ResolutionMetadata({adjudicator: admin, resolutionHash: keccak256("invalid:none")})
        );
    }

    function testResolveSignalAllowsUnderReviewToConfirmed() public {
        MockRiskRegistry directRegistry = new MockRiskRegistry(0.1 ether, admin);
        vm.deal(whitehat, 1 ether);

        vm.prank(whitehat);
        bytes32 reportId = directRegistry.raiseSignal{value: 0.1 ether}(
            address(vault),
            RiskResponseCodes.TARGET_TYPE_VAULT,
            RiskResponseCodes.RISK_DEPEG,
            3,
            bytes32(0),
            abi.encodePacked("evidence:review-window")
        );

        vm.prank(admin);
        directRegistry.resolveSignal(
            reportId,
            IRiskRegistry.Status.UnderReview,
            IRiskRegistry.ResolutionMetadata({adjudicator: admin, resolutionHash: keccak256("under-review")})
        );

        IRiskRegistry.Signal memory underReviewSignal = directRegistry.getSignal(reportId);
        assertEq(uint256(underReviewSignal.status), uint256(IRiskRegistry.Status.UnderReview));

        vm.prank(admin);
        directRegistry.resolveSignal(
            reportId,
            IRiskRegistry.Status.Confirmed,
            IRiskRegistry.ResolutionMetadata({adjudicator: admin, resolutionHash: keccak256("confirmed-after-review")})
        );

        IRiskRegistry.Signal memory confirmedSignal = directRegistry.getSignal(reportId);
        assertEq(uint256(confirmedSignal.status), uint256(IRiskRegistry.Status.Confirmed));
    }

    function testResolveSignalRevertsWhenReResolvingConfirmedSignal() public {
        MockRiskRegistry directRegistry = new MockRiskRegistry(0.1 ether, admin);
        vm.deal(whitehat, 1 ether);

        vm.prank(whitehat);
        bytes32 reportId = directRegistry.raiseSignal{value: 0.1 ether}(
            address(vault),
            RiskResponseCodes.TARGET_TYPE_VAULT,
            RiskResponseCodes.RISK_DEPEG,
            3,
            bytes32(0),
            abi.encodePacked("evidence:confirmed-twice")
        );

        vm.prank(admin);
        directRegistry.resolveSignal(
            reportId,
            IRiskRegistry.Status.Confirmed,
            IRiskRegistry.ResolutionMetadata({adjudicator: admin, resolutionHash: keccak256("confirmed-once")})
        );

        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(MockRiskRegistry.InvalidSourceStatus.selector, IRiskRegistry.Status.Confirmed)
        );
        directRegistry.resolveSignal(
            reportId,
            IRiskRegistry.Status.Resolved,
            IRiskRegistry.ResolutionMetadata({adjudicator: admin, resolutionHash: keccak256("resolved-after-confirmed")})
        );
    }

    function testRecordExecutionRevertsForUnauthorizedReporter() public {
        bytes32 reportId = _raiseAndConfirm(address(vault));

        vm.expectRevert(
            abi.encodeWithSelector(
                MockRiskRegistry.UnauthorizedExecutionReporter.selector, address(this), address(vault)
            )
        );
        registry.recordExecution(
            reportId,
            address(executor),
            RiskResponseCodes.ACTION_PAUSE_DEPOSIT,
            RiskResponseCodes.RESTRICTION_PAUSE_DEPOSIT,
            _executionSnapshotHash(reportId)
        );
    }

    function testResolveLocalEmergencyWithoutActiveStateIsNoOpButEventful() public {
        vm.expectEmit(address(vault));
        emit LocalEmergencyResolved(admin, bytes32(0), bytes32(0), "no-op recovery");
        vm.prank(admin);
        vault.resolveLocalEmergency("no-op recovery");

        (bool emergencyActive, bytes32 activeReport) = vault.emergencyStatus();
        assertFalse(emergencyActive);
        assertEq(activeReport, bytes32(0));
        assertEq(vault.maxDeposit(alice), type(uint256).max);
        assertEq(vault.activeReportId(), bytes32(0));
    }

    function testOwnerCanUpdateTrustedRiskRegistry() public {
        MockRiskRegistry nextRegistry = new MockRiskRegistry(0.2 ether, admin);

        vm.expectEmit(address(vault));
        emit TrustedRiskRegistryUpdated(admin, address(registry), address(nextRegistry));
        vm.prank(admin);
        vault.setTrustedRiskRegistry(address(nextRegistry));

        assertEq(vault.trustedRiskRegistry(), address(nextRegistry));
    }

    function testTriggerEmergencyActionRevertsForSignalBoundToDifferentVault() public {
        bytes32 reportId = _raiseAndConfirm(address(otherVault));

        vm.expectRevert(abi.encodeWithSelector(SafeVault4626.UnsupportedSignal.selector, reportId));
        executor.trigger(address(vault), address(registry), reportId);
    }

    function testTriggerEmergencyActionRevertsWhenSignalIsNotConfirmed() public {
        bytes32 reportId = _raiseOnly(address(vault));

        vm.expectRevert(abi.encodeWithSelector(SafeVault4626.ReportNotConfirmed.selector, reportId));
        executor.trigger(address(vault), address(registry), reportId);
    }

    function _raiseAndConfirm(address target) internal returns (bytes32 reportId) {
        reportId = _raiseOnly(target);

        bytes32 resolutionHash = keccak256("confirmed:slow-depeg");
        vm.expectEmit(address(registry));
        emit SignalResolved(reportId, target, IRiskRegistry.Status.Confirmed, address(adjudicator), resolutionHash);
        vm.prank(admin);
        adjudicator.confirm(reportId, resolutionHash);

        IRiskRegistry.Signal memory signal = registry.getSignal(reportId);
        assertEq(uint256(signal.status), uint256(IRiskRegistry.Status.Confirmed));
        assertEq(signal.targetType, RiskResponseCodes.TARGET_TYPE_VAULT);
    }

    function _raiseOnly(address target) internal returns (bytes32 reportId) {
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
    }

    function _executionSnapshotHash(bytes32 reportId) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                RiskResponseCodes.ACTION_PAUSE_DEPOSIT, RiskResponseCodes.RESTRICTION_PAUSE_DEPOSIT, true, reportId
            )
        );
    }
}
