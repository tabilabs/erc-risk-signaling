// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {MockAdjudicator} from "../src/MockAdjudicator.sol";
import {MockAggregatorRouter} from "../src/MockAggregatorRouter.sol";
import {MockExecutor} from "../src/MockExecutor.sol";
import {IRiskRegistry} from "../src/interfaces/IRiskRegistry.sol";
import {MockRiskRegistry} from "../src/MockRiskRegistry.sol";
import {MockUSDC} from "../src/MockUSDC.sol";
import {RiskAwareConsumerLens} from "../src/RiskAwareConsumerLens.sol";
import {RiskResponseCodes} from "../src/libraries/RiskResponseCodes.sol";
import {RiskStateLens} from "../src/RiskStateLens.sol";
import {SafeVault4626} from "../src/SafeVault4626.sol";
import {RaiseDepegSignal} from "../script/RaiseDepegSignal.s.sol";
import {ReadRiskSnapshot} from "../script/ReadRiskSnapshot.s.sol";
import {RunDepegScenario} from "../script/RunDepegScenario.s.sol";

/// @dev Script guard-rail tests. RunDepegScenario guards are tested in a single
/// serialised function to work around forge's process-global vm.setEnv pollution.
contract ScriptGuardRailsTest is Test {
    bytes32 internal constant REASON_NONE = 0x4e4f4e4500000000000000000000000000000000000000000000000000000000;
    bytes32 internal constant REASON_CONFIRMED_NOT_EXECUTED =
        0x434f4e4649524d45445f4e4f545f455845435554454400000000000000000000;
    bytes32 internal constant REASON_PAUSE_DEPOSIT_ACTIVE =
        0x50415553455f4445504f5349545f414354495645000000000000000000000000;
    bytes32 internal constant REASON_EXECUTED_STATE_MISMATCH =
        0x45584543555445445f53544154455f4d49534d41544348000000000000000000;
    bytes32 internal constant REASON_LOCAL_RECOVERY_WITH_HISTORY =
        0x4c4f43414c5f5245434f564552595f574954485f484953544f52590000000000;

    address internal admin = makeAddr("admin");
    address internal whitehat = makeAddr("whitehat");

    MockUSDC internal asset;
    MockRiskRegistry internal registry;
    MockAdjudicator internal adjudicator;
    MockExecutor internal executor;
    RiskStateLens internal stateLens;
    RiskAwareConsumerLens internal consumerLens;
    MockAggregatorRouter internal router;
    SafeVault4626 internal vault;
    SafeVault4626 internal alternateVault;

    function setUp() public {
        asset = new MockUSDC();
        registry = new MockRiskRegistry(0.1 ether, admin);
        adjudicator = new MockAdjudicator(registry, admin);
        executor = new MockExecutor();
        stateLens = new RiskStateLens();
        consumerLens = new RiskAwareConsumerLens(stateLens);
        router = new MockAggregatorRouter(consumerLens);
        vault = new SafeVault4626(asset, admin);
        alternateVault = new SafeVault4626(asset, admin);

        vm.prank(admin);
        registry.transferOwnership(address(adjudicator));
        vm.prank(admin);
        vault.setTrustedRiskRegistry(address(registry));
        vm.prank(admin);
        alternateVault.setTrustedRiskRegistry(address(registry));
    }

    function testRaiseDepegSignalRevertsWhenSeverityExceedsUint8() public {
        _setEnv("PRIVATE_KEY", vm.toString(uint256(1)));
        _setEnv("REGISTRY", vm.toString(address(registry)));
        _setEnv("TARGET", vm.toString(address(vault)));
        _setEnv("SEVERITY", vm.toString(uint256(256)));

        RaiseDepegSignal script = new RaiseDepegSignal();

        vm.expectRevert(abi.encodeWithSelector(RaiseDepegSignal.SeverityTooHigh.selector, uint256(256)));
        script.run();
    }

    function testReadRiskSnapshotDoesNotRevertWhenNoRouteAvailable() public {
        bytes32 reportId = _raiseAndConfirm(address(vault));
        bytes32 alternateReportId = _raiseAndConfirm(address(alternateVault));

        executor.trigger(address(vault), address(registry), reportId);
        executor.trigger(address(alternateVault), address(registry), alternateReportId);

        _setEnv("LENS", vm.toString(address(stateLens)));
        _setEnv("CONSUMER", vm.toString(address(consumerLens)));
        _setEnv("REGISTRY", vm.toString(address(registry)));
        _setEnv("RESPONDER", vm.toString(address(vault)));
        _setEnv("REPORT_ID", vm.toString(reportId));
        _setEnv("ROUTER", vm.toString(address(router)));
        _setEnv("ALTERNATE_VAULT", vm.toString(address(alternateVault)));
        _setEnv("ALTERNATE_REPORT_ID", vm.toString(alternateReportId));

        ReadRiskSnapshot script = new ReadRiskSnapshot();
        script.run();
    }

    function testReadRiskSnapshotLabelHelpersMatchReviewerOutput() public {
        ReadRiskSnapshot script = new ReadRiskSnapshot();

        assertEq(script.statusLabel(IRiskRegistry.Status.Submitted), "Submitted");
        assertEq(script.statusLabel(IRiskRegistry.Status.Executed), "Executed");
        assertEq(script.decisionLevelLabel(0), "NORMAL");
        assertEq(script.decisionLevelLabel(2), "BLOCK_NEW_DEPOSIT");
        assertEq(script.reasonLabel(REASON_NONE), "NONE");
        assertEq(script.reasonLabel(REASON_CONFIRMED_NOT_EXECUTED), "CONFIRMED_NOT_EXECUTED");
        assertEq(script.reasonLabel(REASON_PAUSE_DEPOSIT_ACTIVE), "PAUSE_DEPOSIT_ACTIVE");
        assertEq(script.reasonLabel(REASON_EXECUTED_STATE_MISMATCH), "EXECUTED_STATE_MISMATCH");
        assertEq(script.reasonLabel(REASON_LOCAL_RECOVERY_WITH_HISTORY), "LOCAL_RECOVERY_WITH_HISTORY");
    }

    /// @dev Tests RunDepegScenario guard-rails via the pure validateInputs function
    /// instead of vm.setEnv + run(). forge shares one OS process across all test suites,
    /// making vm.setEnv unreliable for env-var override across or within tests.
    function testRunDepegScenarioGuardRails() public {
        RunDepegScenario script = new RunDepegScenario();

        // MissingReportId: reportId == bytes32(0) should always revert.
        vm.expectRevert(RunDepegScenario.MissingReportId.selector);
        script.validateInputs(bytes32(0), false, true);

        // NoActionRequested: skipConfirmation=true, triggerExecution=false should revert.
        vm.expectRevert(RunDepegScenario.NoActionRequested.selector);
        script.validateInputs(bytes32(uint256(1)), true, false);

        // Valid inputs should not revert.
        script.validateInputs(bytes32(uint256(1)), false, true);
        script.validateInputs(bytes32(uint256(1)), true, true);
        script.validateInputs(bytes32(uint256(1)), false, false);
    }

    function _raiseAndConfirm(address target) internal returns (bytes32 reportId) {
        vm.deal(whitehat, 1 ether);

        vm.prank(whitehat);
        reportId = registry.raiseSignal{value: 0.1 ether}(
            target, RiskResponseCodes.RISK_DEPEG, 3, bytes32(0), abi.encodePacked("evidence:script-guard")
        );

        vm.prank(admin);
        adjudicator.confirm(reportId, keccak256("confirmed:script-guard"));
    }

    function _setEnv(string memory name, string memory value) internal {
        // forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv(name, value);
    }
}
