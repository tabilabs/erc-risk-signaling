// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

interface IProtocolResponder is IERC165 {
    // resultHash is implementation-defined. In this PoC it anchors the responder's post-execution local state.
    event TrustedRiskRegistryUpdated(
        address indexed updatedBy, address indexed previousRegistry, address indexed newRegistry
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

    function emergencyStatus() external view returns (bool isActive, bytes32 activeReportId);

    function trustedRiskRegistry() external view returns (address registry);

    function getActiveRestrictions() external view returns (bytes32[] memory restrictionIds);

    function triggerEmergencyAction(address registry, bytes32 reportId) external;

    function resolveLocalEmergency(string calldata reason) external;
}
