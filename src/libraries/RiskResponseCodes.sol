// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IRiskRegistry} from "../interfaces/IRiskRegistry.sol";

library RiskResponseCodes {
    bytes32 internal constant RISK_DEPEG = keccak256("RISK_DEPEG");
    bytes32 internal constant ACTION_PAUSE_DEPOSIT = keccak256("ACTION_PAUSE_DEPOSIT");
    bytes32 internal constant RESTRICTION_PAUSE_DEPOSIT = keccak256("PAUSE_DEPOSIT");

    // Decision levels — shared by RiskAwareConsumerLens and consumer scripts.
    uint8 internal constant LEVEL_NORMAL = 0;
    uint8 internal constant LEVEL_WARNING = 1;
    uint8 internal constant LEVEL_BLOCK_NEW_DEPOSIT = 2;
    uint8 internal constant LEVEL_RECOVERED_HISTORY = 3;

    // Reason codes — shared by RiskAwareConsumerLens and consumer scripts.
    bytes32 internal constant REASON_NONE = "NONE";
    bytes32 internal constant REASON_CONFIRMED_NOT_EXECUTED = "CONFIRMED_NOT_EXECUTED";
    bytes32 internal constant REASON_PAUSE_DEPOSIT_ACTIVE = "PAUSE_DEPOSIT_ACTIVE";
    bytes32 internal constant REASON_EXECUTED_STATE_MISMATCH = "EXECUTED_STATE_MISMATCH";
    bytes32 internal constant REASON_LOCAL_RECOVERY_WITH_HISTORY = "LOCAL_RECOVERY_WITH_HISTORY";

    function statusLabel(IRiskRegistry.Status status) internal pure returns (string memory) {
        if (status == IRiskRegistry.Status.None) return "None";
        if (status == IRiskRegistry.Status.Submitted) return "Submitted";
        if (status == IRiskRegistry.Status.UnderReview) return "UnderReview";
        if (status == IRiskRegistry.Status.Confirmed) return "Confirmed";
        if (status == IRiskRegistry.Status.Rejected) return "Rejected";
        if (status == IRiskRegistry.Status.Expired) return "Expired";
        if (status == IRiskRegistry.Status.Executed) return "Executed";
        if (status == IRiskRegistry.Status.Resolved) return "Resolved";
        return "Unknown";
    }

    function decisionLevelLabel(uint8 level) internal pure returns (string memory) {
        if (level == LEVEL_NORMAL) return "NORMAL";
        if (level == LEVEL_WARNING) return "WARNING";
        if (level == LEVEL_BLOCK_NEW_DEPOSIT) return "BLOCK_NEW_DEPOSIT";
        if (level == LEVEL_RECOVERED_HISTORY) return "RECOVERED_HISTORY";
        return "UNKNOWN";
    }

    function reasonLabel(bytes32 code) internal pure returns (string memory) {
        if (code == REASON_NONE) return "NONE";
        if (code == REASON_CONFIRMED_NOT_EXECUTED) return "CONFIRMED_NOT_EXECUTED";
        if (code == REASON_PAUSE_DEPOSIT_ACTIVE) return "PAUSE_DEPOSIT_ACTIVE";
        if (code == REASON_EXECUTED_STATE_MISMATCH) return "EXECUTED_STATE_MISMATCH";
        if (code == REASON_LOCAL_RECOVERY_WITH_HISTORY) return "LOCAL_RECOVERY_WITH_HISTORY";
        return "UNKNOWN";
    }
}
