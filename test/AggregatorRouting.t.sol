// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {IRiskRegistry} from "../src/interfaces/IRiskRegistry.sol";
import {MockAdjudicator} from "../src/MockAdjudicator.sol";
import {MockAggregatorRouter} from "../src/MockAggregatorRouter.sol";
import {MockExecutor} from "../src/MockExecutor.sol";
import {MockRiskRegistry} from "../src/MockRiskRegistry.sol";
import {MockUSDC} from "../src/MockUSDC.sol";
import {RiskAwareConsumerLens} from "../src/RiskAwareConsumerLens.sol";
import {SafeVault4626} from "../src/SafeVault4626.sol";
import {RiskResponseCodes} from "../src/libraries/RiskResponseCodes.sol";
import {RiskStateLens} from "../src/RiskStateLens.sol";

contract AggregatorRoutingTest is Test {
    event ExecutionTriggered(
        address indexed responder, address indexed registry, bytes32 indexed reportId, address caller
    );
    bytes32 internal constant SAFE_VAULT_REPORT_ID = keccak256("safe-vault:no-report");

    address internal admin = makeAddr("admin");
    address internal whitehat = makeAddr("whitehat");
    address internal user = makeAddr("user");

    MockUSDC internal asset;
    MockRiskRegistry internal registry;
    MockAdjudicator internal adjudicator;
    MockExecutor internal executor;
    RiskStateLens internal stateLens;
    RiskAwareConsumerLens internal consumerLens;
    MockAggregatorRouter internal router;
    SafeVault4626 internal riskyVault;
    SafeVault4626 internal safeVault;

    function setUp() public {
        asset = new MockUSDC();
        registry = new MockRiskRegistry(0.1 ether, admin);
        adjudicator = new MockAdjudicator(registry, admin);
        executor = new MockExecutor();
        stateLens = new RiskStateLens();
        consumerLens = new RiskAwareConsumerLens(stateLens);
        router = new MockAggregatorRouter(consumerLens);
        riskyVault = new SafeVault4626(asset, admin);
        safeVault = new SafeVault4626(asset, admin);

        vm.prank(admin);
        registry.transferOwnership(address(adjudicator));
        vm.prank(admin);
        riskyVault.setTrustedRiskRegistry(address(registry));
        vm.prank(admin);
        safeVault.setTrustedRiskRegistry(address(registry));

        asset.mint(user, 1_000_000e6);

        vm.prank(user);
        asset.approve(address(riskyVault), type(uint256).max);
        vm.prank(user);
        riskyVault.deposit(100e6, user);
    }

    function testRouterDoesNotSkipVaultWhenSignalIsConfirmedButNotExecuted() public {
        bytes32 reportId = _raiseAndConfirm(address(riskyVault));
        RiskAwareConsumerLens.Decision memory routeDecision =
            consumerLens.decision(address(registry), address(riskyVault), reportId);
        RiskAwareConsumerLens.Decision memory routerDecision =
            router.getRouteDecision(address(registry), address(riskyVault), reportId);

        address[] memory vaults = new address[](2);
        vaults[0] = address(riskyVault);
        vaults[1] = address(safeVault);

        bytes32[] memory reportIds = new bytes32[](2);
        reportIds[0] = reportId;
        reportIds[1] = SAFE_VAULT_REPORT_ID;

        assertEq(routeDecision.reasonCode, consumerLens.REASON_CONFIRMED_NOT_EXECUTED());
        assertTrue(routeDecision.shouldWarn);
        assertFalse(routeDecision.shouldBlockNewDeposit);
        assertFalse(routeDecision.shouldSkipVault);
        assertTrue(routeDecision.shouldAllowExit);
        assertEq(routerDecision.reasonCode, routeDecision.reasonCode);
        assertEq(routerDecision.shouldSkipVault, routeDecision.shouldSkipVault);
        assertEq(routerDecision.shouldAllowExit, routeDecision.shouldAllowExit);

        assertFalse(router.shouldSkipVault(address(registry), address(riskyVault), reportId));
        assertEq(router.selectDepositRoute(address(registry), vaults, reportIds), address(riskyVault));
        assertTrue(router.canRouteExit(address(registry), address(riskyVault), reportId, user, 50e6));
    }

    function testRouterSkipsAfterExecutionAndRoutesAgainAfterLocalRecovery() public {
        bytes32 reportId = _raiseAndConfirm(address(riskyVault));

        address[] memory vaults = new address[](2);
        vaults[0] = address(riskyVault);
        vaults[1] = address(safeVault);

        bytes32[] memory reportIds = new bytes32[](2);
        reportIds[0] = reportId;
        reportIds[1] = SAFE_VAULT_REPORT_ID;

        vm.expectEmit(address(executor));
        emit ExecutionTriggered(address(riskyVault), address(registry), reportId, address(this));
        executor.trigger(address(riskyVault), address(registry), reportId);

        IRiskRegistry.Signal memory signalAfterExecution = registry.getSignal(reportId);
        RiskAwareConsumerLens.Decision memory executedDecision =
            consumerLens.decision(address(registry), address(riskyVault), reportId);
        RiskAwareConsumerLens.Decision memory executedRouterDecision =
            router.getRouteDecision(address(registry), address(riskyVault), reportId);
        assertEq(uint256(signalAfterExecution.status), uint256(IRiskRegistry.Status.Confirmed));
        assertTrue(registry.getExecution(reportId).recorded);
        assertTrue(executedDecision.shouldSkipVault);
        assertTrue(executedDecision.shouldBlockNewDeposit);
        assertTrue(executedDecision.shouldAllowExit);
        assertEq(executedRouterDecision.reasonCode, executedDecision.reasonCode);
        assertEq(executedRouterDecision.shouldSkipVault, executedDecision.shouldSkipVault);
        assertEq(executedRouterDecision.shouldAllowExit, executedDecision.shouldAllowExit);
        assertTrue(router.shouldSkipVault(address(registry), address(riskyVault), reportId));
        assertFalse(router.shouldSkipVault(address(registry), address(safeVault), SAFE_VAULT_REPORT_ID));
        assertTrue(router.canRouteExit(address(registry), address(riskyVault), reportId, user, 50e6));
        assertEq(router.selectDepositRoute(address(registry), vaults, reportIds), address(safeVault));

        vm.prank(admin);
        riskyVault.resolveLocalEmergency("peg restored locally");

        RiskAwareConsumerLens.Decision memory recoveredDecision =
            consumerLens.decision(address(registry), address(riskyVault), reportId);
        RiskAwareConsumerLens.Decision memory recoveredRouterDecision =
            router.getRouteDecision(address(registry), address(riskyVault), reportId);
        assertEq(recoveredDecision.reasonCode, consumerLens.REASON_LOCAL_RECOVERY_WITH_HISTORY());
        assertTrue(recoveredDecision.shouldWarn);
        assertFalse(recoveredDecision.shouldBlockNewDeposit);
        assertFalse(recoveredDecision.shouldSkipVault);
        assertTrue(recoveredDecision.shouldAllowExit);
        assertEq(recoveredRouterDecision.reasonCode, recoveredDecision.reasonCode);
        assertEq(recoveredRouterDecision.shouldSkipVault, recoveredDecision.shouldSkipVault);
        assertEq(recoveredRouterDecision.shouldAllowExit, recoveredDecision.shouldAllowExit);
        assertFalse(router.shouldSkipVault(address(registry), address(riskyVault), reportId));
        assertTrue(router.canRouteExit(address(registry), address(riskyVault), reportId, user, 50e6));
        assertEq(router.selectDepositRoute(address(registry), vaults, reportIds), address(riskyVault));
    }

    function testRouterDoesNotSkipVaultForConfirmedSignalFromUntrustedRegistry() public {
        MockRiskRegistry rogueRegistry = new MockRiskRegistry(0.1 ether, admin);
        vm.deal(whitehat, 1 ether);

        vm.prank(whitehat);
        bytes32 rogueReportId = rogueRegistry.raiseSignal{value: 0.1 ether}(
            address(riskyVault),
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

        address[] memory vaults = new address[](2);
        vaults[0] = address(riskyVault);
        vaults[1] = address(safeVault);

        bytes32[] memory reportIds = new bytes32[](2);
        reportIds[0] = rogueReportId;
        reportIds[1] = SAFE_VAULT_REPORT_ID;

        assertFalse(router.shouldSkipVault(address(rogueRegistry), address(riskyVault), rogueReportId));
        assertTrue(router.canRouteExit(address(rogueRegistry), address(riskyVault), rogueReportId, user, 50e6));
        assertEq(router.selectDepositRoute(address(rogueRegistry), vaults, reportIds), address(riskyVault));
    }

    function testRouterReturnsNormalDecisionBeforeAnySignal() public view {
        RiskAwareConsumerLens.Decision memory consumerDecision =
            consumerLens.decision(address(registry), address(riskyVault), bytes32(0));
        RiskAwareConsumerLens.Decision memory routerDecision =
            router.getRouteDecision(address(registry), address(riskyVault), bytes32(0));

        assertEq(consumerDecision.reasonCode, consumerLens.REASON_NONE());
        assertEq(routerDecision.reasonCode, consumerDecision.reasonCode);
        assertEq(routerDecision.shouldSkipVault, consumerDecision.shouldSkipVault);
        assertEq(routerDecision.shouldAllowExit, consumerDecision.shouldAllowExit);
        assertFalse(router.shouldSkipVault(address(registry), address(riskyVault), bytes32(0)));
    }

    function testSelectDepositRouteRevertsOnInputLengthMismatch() public {
        address[] memory vaults = new address[](2);
        vaults[0] = address(riskyVault);
        vaults[1] = address(safeVault);

        bytes32[] memory reportIds = new bytes32[](1);
        reportIds[0] = SAFE_VAULT_REPORT_ID;

        vm.expectRevert(MockAggregatorRouter.InputLengthMismatch.selector);
        router.selectDepositRoute(address(registry), vaults, reportIds);
    }

    function testSelectDepositRouteRevertsWhenAllVaultsAreSkipped() public {
        bytes32 riskyReportId = _raiseAndConfirm(address(riskyVault));
        bytes32 safeReportId = _raiseAndConfirm(address(safeVault));

        executor.trigger(address(riskyVault), address(registry), riskyReportId);
        executor.trigger(address(safeVault), address(registry), safeReportId);

        assertTrue(router.shouldSkipVault(address(registry), address(riskyVault), riskyReportId));
        assertTrue(router.shouldSkipVault(address(registry), address(safeVault), safeReportId));

        address[] memory vaults = new address[](2);
        vaults[0] = address(riskyVault);
        vaults[1] = address(safeVault);

        bytes32[] memory reportIds = new bytes32[](2);
        reportIds[0] = riskyReportId;
        reportIds[1] = safeReportId;

        vm.expectRevert(MockAggregatorRouter.NoRouteAvailable.selector);
        router.selectDepositRoute(address(registry), vaults, reportIds);
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
