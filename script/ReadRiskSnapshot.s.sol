// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

import {console2} from "forge-std/console2.sol";
import {Script} from "forge-std/Script.sol";

import {IRiskRegistry} from "../src/interfaces/IRiskRegistry.sol";
import {MockAggregatorRouter} from "../src/MockAggregatorRouter.sol";
import {RiskAwareConsumerLens} from "../src/RiskAwareConsumerLens.sol";
import {RiskResponseCodes} from "../src/libraries/RiskResponseCodes.sol";
import {RiskStateLens} from "../src/RiskStateLens.sol";

contract ReadRiskSnapshot is Script {
    function run() external view {
        address lensAddress = vm.envAddress("LENS");
        address consumerAddress = vm.envAddress("CONSUMER");
        address registryAddress = vm.envAddress("REGISTRY");
        address responderAddress = vm.envAddress("RESPONDER");
        bytes32 reportId = vm.envBytes32("REPORT_ID");
        address routerAddress = vm.envOr("ROUTER", address(0));
        address alternateVault = vm.envOr("ALTERNATE_VAULT", address(0));
        bytes32 alternateReportId = vm.envOr("ALTERNATE_REPORT_ID", bytes32(0));
        address exitOwner = vm.envOr("EXIT_OWNER", address(0));
        uint256 exitShares = vm.envOr("EXIT_SHARES", uint256(0));

        RiskStateLens.Snapshot memory snapshot =
            RiskStateLens(lensAddress).snapshot(registryAddress, responderAddress, reportId);
        RiskAwareConsumerLens.Decision memory decision =
            RiskAwareConsumerLens(consumerAddress).decision(registryAddress, responderAddress, reportId);
        bool hasAlternateVault = alternateVault != address(0);
        RiskAwareConsumerLens.Decision memory alternateDecision;

        console2.log("reportId");
        console2.logBytes32(snapshot.reportId);
        console2.log("registryStatus", uint256(snapshot.registryStatus));
        console2.log("registryStatusLabel", statusLabel(snapshot.registryStatus));
        console2.log("target", snapshot.target);
        console2.log("targetType");
        console2.logBytes32(snapshot.targetType);
        console2.log("riskType");
        console2.logBytes32(snapshot.riskType);
        console2.log("hasExecutionRecord", snapshot.hasExecutionRecord);
        console2.log("isEmergencyActive", snapshot.isEmergencyActive);
        console2.log("activeReportId");
        console2.logBytes32(snapshot.activeReportId);
        console2.log("restrictionCount", snapshot.restrictionIds.length);
        for (uint256 i = 0; i < snapshot.restrictionIds.length; ++i) {
            console2.log("restrictionId");
            console2.logBytes32(snapshot.restrictionIds[i]);
        }
        console2.log("isExecutionConsistent", snapshot.isExecutionConsistent);

        console2.log("shouldBlockNewDeposit", decision.shouldBlockNewDeposit);
        console2.log("shouldAllowExit", decision.shouldAllowExit);
        console2.log("shouldWarn", decision.shouldWarn);
        console2.log("shouldSkipVault", decision.shouldSkipVault);
        console2.log("decisionLevel", decision.decisionLevel);
        console2.log("decisionLevelLabel", decisionLevelLabel(decision.decisionLevel));
        console2.log("reasonCode");
        console2.logBytes32(decision.reasonCode);
        console2.log("reasonCodeLabel", reasonLabel(decision.reasonCode));

        if (hasAlternateVault) {
            alternateDecision =
                RiskAwareConsumerLens(consumerAddress).decision(registryAddress, alternateVault, alternateReportId);
            console2.log("alternateVault", alternateVault);
            console2.log("alternateShouldSkipVault", alternateDecision.shouldSkipVault);
            console2.log("alternateReasonCode");
            console2.logBytes32(alternateDecision.reasonCode);
            console2.log("alternateReasonCodeLabel", reasonLabel(alternateDecision.reasonCode));
        }

        if (routerAddress != address(0)) {
            MockAggregatorRouter router = MockAggregatorRouter(routerAddress);
            RiskAwareConsumerLens.Decision memory routeDecision =
                router.getRouteDecision(registryAddress, responderAddress, reportId);

            console2.log("routerDecisionMatchesConsumer", _sameDecision(decision, routeDecision));
            console2.log("routerShouldSkipVault", router.shouldSkipVault(registryAddress, responderAddress, reportId));

            if (exitOwner != address(0) && exitShares > 0) {
                console2.log(
                    "routerCanRouteExit",
                    router.canRouteExit(registryAddress, responderAddress, reportId, exitOwner, exitShares)
                );
            }

            if (hasAlternateVault) {
                RiskAwareConsumerLens.Decision memory alternateRouteDecision =
                    router.getRouteDecision(registryAddress, alternateVault, alternateReportId);

                console2.log(
                    "alternateRouterDecisionMatchesConsumer", _sameDecision(alternateDecision, alternateRouteDecision)
                );
                console2.log(
                    "alternateRouterShouldSkipVault",
                    router.shouldSkipVault(registryAddress, alternateVault, alternateReportId)
                );

                address[] memory vaults = new address[](2);
                vaults[0] = responderAddress;
                vaults[1] = alternateVault;

                bytes32[] memory reportIds = new bytes32[](2);
                reportIds[0] = reportId;
                reportIds[1] = alternateReportId;

                try router.selectDepositRoute(registryAddress, vaults, reportIds) returns (address selectedVault) {
                    console2.log("routerHasSelectedDepositRoute", true);
                    console2.log("routerNoRouteAvailable", false);
                    console2.log("selectedDepositRoute", selectedVault);
                } catch (bytes memory revertData) {
                    if (_matchesSelector(revertData, MockAggregatorRouter.NoRouteAvailable.selector)) {
                        console2.log("routerHasSelectedDepositRoute", false);
                        console2.log("routerNoRouteAvailable", true);
                    } else {
                        _revertBytes(revertData);
                    }
                }
            }
        }
    }

    function _sameDecision(RiskAwareConsumerLens.Decision memory lhs, RiskAwareConsumerLens.Decision memory rhs)
        internal
        pure
        returns (bool)
    {
        if (
            lhs.reportId != rhs.reportId || lhs.shouldBlockNewDeposit != rhs.shouldBlockNewDeposit
                || lhs.shouldAllowExit != rhs.shouldAllowExit || lhs.shouldWarn != rhs.shouldWarn
                || lhs.shouldSkipVault != rhs.shouldSkipVault || lhs.isExecutionConsistent != rhs.isExecutionConsistent
                || lhs.decisionLevel != rhs.decisionLevel || lhs.reasonCode != rhs.reasonCode
                || lhs.restrictionIds.length != rhs.restrictionIds.length
        ) {
            return false;
        }

        for (uint256 i = 0; i < lhs.restrictionIds.length; ++i) {
            if (lhs.restrictionIds[i] != rhs.restrictionIds[i]) {
                return false;
            }
        }

        return true;
    }

    function statusLabel(IRiskRegistry.Status status) public pure returns (string memory) {
        return RiskResponseCodes.statusLabel(status);
    }

    function decisionLevelLabel(uint8 level) public pure returns (string memory) {
        return RiskResponseCodes.decisionLevelLabel(level);
    }

    function reasonLabel(bytes32 code) public pure returns (string memory) {
        return RiskResponseCodes.reasonLabel(code);
    }

    function _matchesSelector(bytes memory revertData, bytes4 selector) internal pure returns (bool) {
        if (revertData.length < 4) {
            return false;
        }

        bytes4 actualSelector;
        assembly {
            actualSelector := mload(add(revertData, 0x20))
        }

        return actualSelector == selector;
    }

    function _revertBytes(bytes memory revertData) internal pure {
        assembly {
            revert(add(revertData, 0x20), mload(revertData))
        }
    }
}
