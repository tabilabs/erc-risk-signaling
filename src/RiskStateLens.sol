// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

import {IRiskRegistry} from "./interfaces/IRiskRegistry.sol";
import {IProtocolResponder} from "./interfaces/IProtocolResponder.sol";

contract RiskStateLens {
    bytes4 private constant _EMERGENCY_STATUS_SELECTOR = bytes4(keccak256("emergencyStatus()"));

    struct Snapshot {
        bytes32 reportId;
        IRiskRegistry.Status registryStatus;
        address target;
        bytes32 targetType;
        bytes32 riskType;
        bool isTargetMatch;
        bool hasExecutionRecord;
        bool hasEmergencyStatusHelper;
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
        IRiskRegistry.ExecutionRecord memory execution = IRiskRegistry(registry).getExecution(reportId);
        bytes32[] memory restrictionIds = IProtocolResponder(responder).getActiveRestrictions();
        bool isTargetMatch = signal.target == responder;
        (bool hasEmergencyStatusHelper, bool isEmergencyActive, bytes32 activeReportId) =
            _readEmergencyStatus(responder);

        state = Snapshot({
            reportId: reportId,
            registryStatus: signal.status,
            target: signal.target,
            targetType: signal.targetType,
            riskType: signal.riskType,
            isTargetMatch: isTargetMatch,
            hasExecutionRecord: execution.recorded,
            hasEmergencyStatusHelper: hasEmergencyStatusHelper,
            isEmergencyActive: isEmergencyActive,
            activeReportId: activeReportId,
            restrictionIds: restrictionIds,
            isExecutionConsistent: _isExecutionConsistent(
                signal.status,
                execution.recorded,
                reportId,
                activeReportId,
                restrictionIds,
                isTargetMatch,
                hasEmergencyStatusHelper,
                isEmergencyActive
            )
        });
    }

    function _isExecutionConsistent(
        IRiskRegistry.Status registryStatus,
        bool hasExecutionRecord,
        bytes32 reportId,
        bytes32 activeReportId,
        bytes32[] memory restrictionIds,
        bool isTargetMatch,
        bool hasEmergencyStatusHelper,
        bool isEmergencyActive
    ) private pure returns (bool) {
        if (!(isTargetMatch && registryStatus == IRiskRegistry.Status.Confirmed && hasExecutionRecord)) {
            return false;
        }
        if (restrictionIds.length == 0) {
            return false;
        }
        if (!hasEmergencyStatusHelper) {
            return true;
        }
        return isEmergencyActive && activeReportId == reportId;
    }

    function _readEmergencyStatus(address responder) private view returns (bool hasHelper, bool isActive, bytes32 reportId)
    {
        (bool ok, bytes memory data) = responder.staticcall(abi.encodeWithSelector(_EMERGENCY_STATUS_SELECTOR));
        if (!ok || data.length < 64) {
            return (false, false, bytes32(0));
        }

        (isActive, reportId) = abi.decode(data, (bool, bytes32));
        return (true, isActive, reportId);
    }
}
