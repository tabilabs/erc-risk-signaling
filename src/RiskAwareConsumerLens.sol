// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

import {IRiskRegistry} from "./interfaces/IRiskRegistry.sol";
import {RiskResponseCodes} from "./libraries/RiskResponseCodes.sol";
import {RiskStateLens} from "./RiskStateLens.sol";

contract RiskAwareConsumerLens {
    // Re-export constants from RiskResponseCodes for external consumers that read via this contract.
    uint8 public constant LEVEL_NORMAL = RiskResponseCodes.LEVEL_NORMAL;
    uint8 public constant LEVEL_WARNING = RiskResponseCodes.LEVEL_WARNING;
    uint8 public constant LEVEL_BLOCK_NEW_DEPOSIT = RiskResponseCodes.LEVEL_BLOCK_NEW_DEPOSIT;
    uint8 public constant LEVEL_RECOVERED_HISTORY = RiskResponseCodes.LEVEL_RECOVERED_HISTORY;

    bytes32 public constant REASON_NONE = RiskResponseCodes.REASON_NONE;
    bytes32 public constant REASON_CONFIRMED_NOT_EXECUTED = RiskResponseCodes.REASON_CONFIRMED_NOT_EXECUTED;
    bytes32 public constant REASON_PAUSE_DEPOSIT_ACTIVE = RiskResponseCodes.REASON_PAUSE_DEPOSIT_ACTIVE;
    bytes32 public constant REASON_EXECUTED_STATE_MISMATCH = RiskResponseCodes.REASON_EXECUTED_STATE_MISMATCH;
    bytes32 public constant REASON_LOCAL_RECOVERY_WITH_HISTORY = RiskResponseCodes.REASON_LOCAL_RECOVERY_WITH_HISTORY;

    RiskStateLens public immutable LENS;

    struct Decision {
        bytes32 reportId;
        bool shouldBlockNewDeposit;
        bool shouldAllowExit;
        bool shouldWarn;
        bool shouldSkipVault;
        bool isExecutionConsistent;
        uint8 decisionLevel;
        bytes32 reasonCode;
        bytes32[] restrictionIds;
    }

    constructor(RiskStateLens lens_) {
        LENS = lens_;
    }

    function decision(address registry, address responder, bytes32 reportId)
        external
        view
        returns (Decision memory result)
    {
        RiskStateLens.Snapshot memory state = LENS.snapshot(registry, responder, reportId);
        bool hasPauseDepositRestriction =
            _containsRestriction(state.restrictionIds, RiskResponseCodes.RESTRICTION_PAUSE_DEPOSIT);

        result = Decision({
            reportId: reportId,
            shouldBlockNewDeposit: false,
            shouldAllowExit: true,
            shouldWarn: false,
            shouldSkipVault: false,
            isExecutionConsistent: state.isExecutionConsistent,
            decisionLevel: LEVEL_NORMAL,
            reasonCode: REASON_NONE,
            restrictionIds: state.restrictionIds
        });

        // Missing reports and foreign reports should be ignored explicitly instead of
        // relying on the registry's default zero-value status to fall through.
        if (state.target == address(0) || !state.isTargetMatch) {
            return result;
        }

        if (hasPauseDepositRestriction && state.isEmergencyActive) {
            result.shouldBlockNewDeposit = true;
            result.shouldWarn = true;
            result.shouldSkipVault = true;
            result.decisionLevel = LEVEL_BLOCK_NEW_DEPOSIT;
            result.reasonCode = REASON_PAUSE_DEPOSIT_ACTIVE;
            return result;
        }

        if (state.registryStatus == IRiskRegistry.Status.Confirmed) {
            result.shouldWarn = true;
            if (!state.hasExecutionRecord) {
                result.decisionLevel = LEVEL_WARNING;
                result.reasonCode = REASON_CONFIRMED_NOT_EXECUTED;
                return result;
            }

            if (!state.isEmergencyActive && state.activeReportId == bytes32(0) && state.restrictionIds.length == 0) {
                result.decisionLevel = LEVEL_RECOVERED_HISTORY;
                result.reasonCode = REASON_LOCAL_RECOVERY_WITH_HISTORY;
                return result;
            }

            result.decisionLevel = LEVEL_WARNING;
            result.reasonCode = REASON_EXECUTED_STATE_MISMATCH;
            return result;
        }

        if (state.registryStatus == IRiskRegistry.Status.Resolved && state.hasExecutionRecord) {
            result.shouldWarn = true;
            if (!state.isEmergencyActive && state.activeReportId == bytes32(0) && state.restrictionIds.length == 0) {
                result.decisionLevel = LEVEL_RECOVERED_HISTORY;
                result.reasonCode = REASON_LOCAL_RECOVERY_WITH_HISTORY;
            } else {
                result.decisionLevel = LEVEL_WARNING;
                result.reasonCode = REASON_EXECUTED_STATE_MISMATCH;
            }
            return result;
        }
    }

    function _containsRestriction(bytes32[] memory restrictionIds, bytes32 restrictionId) private pure returns (bool) {
        for (uint256 i = 0; i < restrictionIds.length; ++i) {
            if (restrictionIds[i] == restrictionId) {
                return true;
            }
        }
        return false;
    }
}
