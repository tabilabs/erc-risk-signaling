// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IRiskRegistry} from "./interfaces/IRiskRegistry.sol";
import {IProtocolResponder} from "./interfaces/IProtocolResponder.sol";

contract RiskStateLens {
    struct Snapshot {
        bytes32 reportId;
        IRiskRegistry.Status registryStatus;
        address target;
        bytes32 riskType;
        bool isTargetMatch;
        bool isEmergencyActive;
        bytes32 activeReportId;
        bytes32[] restrictionIds;
        bool isExecutionConsistent;
    }

    function snapshot(address registry, address responder, bytes32 reportId)
        external
        view
        returns (Snapshot memory state)
    {
        IRiskRegistry.Signal memory signal = IRiskRegistry(registry).getSignal(reportId);
        (bool isEmergencyActive, bytes32 activeReportId) = IProtocolResponder(responder).emergencyStatus();
        bytes32[] memory restrictionIds = IProtocolResponder(responder).getActiveRestrictions();
        bool isTargetMatch = signal.target == responder;

        state = Snapshot({
            reportId: reportId,
            registryStatus: signal.status,
            target: signal.target,
            riskType: signal.riskType,
            isTargetMatch: isTargetMatch,
            isEmergencyActive: isEmergencyActive,
            activeReportId: activeReportId,
            restrictionIds: restrictionIds,
            isExecutionConsistent: _isExecutionConsistent(
                signal.status, reportId, activeReportId, restrictionIds, isTargetMatch
            )
        });
    }

    function _isExecutionConsistent(
        IRiskRegistry.Status registryStatus,
        bytes32 reportId,
        bytes32 activeReportId,
        bytes32[] memory restrictionIds,
        bool isTargetMatch
    ) private pure returns (bool) {
        return isTargetMatch && registryStatus == IRiskRegistry.Status.Executed && activeReportId == reportId
            && restrictionIds.length > 0;
    }
}
