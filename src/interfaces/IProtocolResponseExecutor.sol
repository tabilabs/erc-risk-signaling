// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

interface IProtocolResponseExecutor is IERC165 {
    event EmergencyActionExecuted(
        bytes32 indexed reportId,
        address indexed registry,
        address indexed executor,
        bytes32 actionId,
        bytes32 restrictionId,
        bytes32 resultHash
    );

    function triggerEmergencyAction(address registry, bytes32 reportId) external;
}
