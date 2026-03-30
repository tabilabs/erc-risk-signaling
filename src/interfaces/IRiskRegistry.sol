// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IRiskRegistry {
    enum Status {
        None,
        Submitted,
        UnderReview,
        Confirmed,
        Rejected,
        Expired,
        Executed,
        Resolved
    }

    struct Signal {
        address producer;
        address target;
        bytes32 riskType;
        uint8 severity;
        bytes32 dependencyRef;
        bytes evidence;
        uint256 bond;
        Status status;
        address adjudicator;
        bytes32 resolutionHash;
    }

    event SignalRaised(
        bytes32 indexed reportId,
        address indexed producer,
        address indexed target,
        bytes32 riskType,
        uint8 severity,
        bytes32 dependencyRef,
        uint256 bond
    );

    event SignalResolved(
        bytes32 indexed reportId, Status indexed status, address indexed adjudicator, bytes32 resolutionHash
    );

    // resultHash is implementation-defined. In this PoC it anchors the responder's post-execution local state.
    event SignalExecutionRecorded(
        bytes32 indexed reportId,
        address indexed target,
        address indexed executor,
        bytes32 actionId,
        bytes32 restrictionId,
        bytes32 resultHash
    );

    function raiseSignal(
        address target,
        bytes32 riskType,
        uint8 severity,
        bytes32 dependencyRef,
        bytes calldata evidence
    ) external payable returns (bytes32 reportId);

    function resolveSignal(bytes32 reportId, Status finalStatus, bytes32 resolutionHash) external;

    function recordExecution(
        bytes32 reportId,
        address executor,
        bytes32 actionId,
        bytes32 restrictionId,
        bytes32 resultHash
    ) external;

    function getSignal(bytes32 reportId) external view returns (Signal memory signal);
}
