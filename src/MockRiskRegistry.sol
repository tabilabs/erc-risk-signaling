// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {IRiskRegistry} from "./interfaces/IRiskRegistry.sol";

contract MockRiskRegistry is Ownable, IRiskRegistry {
    uint256 public immutable BOND_FLOOR;
    uint256 public nextNonce;

    mapping(bytes32 => Signal) private signals;
    mapping(bytes32 => ResolutionMetadata) private resolutions;
    mapping(bytes32 => ExecutionRecord) private executions;

    error BondTooLow(uint256 provided, uint256 requiredBond);
    error SignalNotFound(bytes32 reportId);
    error InvalidFinalStatus(Status status);
    error InvalidSourceStatus(Status status);
    error InvalidExecutionStatus(Status status);
    error ExecutionAlreadyRecorded(bytes32 reportId);
    error UnauthorizedExecutionReporter(address caller, address expectedTarget);

    constructor(uint256 requiredBondFloor, address initialOwner) Ownable(initialOwner) {
        BOND_FLOOR = requiredBondFloor;
    }

    function raiseSignal(
        address target,
        bytes32 targetType,
        bytes32 riskType,
        uint8 severity,
        bytes32 dependencyRef,
        bytes calldata evidence
    ) external payable returns (bytes32 reportId) {
        if (msg.value < BOND_FLOOR) {
            revert BondTooLow(msg.value, BOND_FLOOR);
        }

        reportId = keccak256(
            abi.encode(block.chainid, address(this), msg.sender, target, riskType, severity, dependencyRef, nextNonce++)
        );

        Signal storage signal = signals[reportId];
        signal.producer = msg.sender;
        signal.target = target;
        signal.targetType = targetType;
        signal.riskType = riskType;
        signal.severity = severity;
        signal.dependencyRef = dependencyRef;
        signal.evidence = evidence;
        signal.bond = msg.value;
        signal.status = Status.Submitted;

        emit SignalRaised(reportId, msg.sender, target, targetType, riskType, severity, dependencyRef, msg.value);
    }

    function resolveSignal(bytes32 reportId, Status finalStatus, ResolutionMetadata calldata resolution)
        external
        onlyOwner
    {
        Signal storage signal = signals[reportId];
        if (signal.target == address(0)) {
            revert SignalNotFound(reportId);
        }

        // State machine: Submitted can move into review or a terminal adjudication;
        // UnderReview can only move forward into a terminal adjudication.
        if (signal.status != Status.Submitted && signal.status != Status.UnderReview) {
            revert InvalidSourceStatus(signal.status);
        }

        bool validTransition = signal.status == Status.Submitted
            ? (finalStatus == Status.UnderReview || finalStatus == Status.Confirmed || finalStatus == Status.Rejected
                    || finalStatus == Status.Expired || finalStatus == Status.Resolved)
            : (finalStatus == Status.Confirmed || finalStatus == Status.Rejected || finalStatus == Status.Expired
                    || finalStatus == Status.Resolved);

        if (!validTransition) {
            revert InvalidFinalStatus(finalStatus);
        }

        signal.status = finalStatus;
        resolutions[reportId] = resolution;

        emit SignalResolved(reportId, signal.target, finalStatus, resolution.adjudicator, resolution.resolutionHash);
    }

    function recordExecution(
        bytes32 reportId,
        address executor,
        bytes32 actionId,
        bytes32 restrictionId,
        bytes32 resultHash
    ) external {
        Signal storage signal = signals[reportId];
        if (signal.target == address(0)) {
            revert SignalNotFound(reportId);
        }
        if (msg.sender != signal.target) {
            revert UnauthorizedExecutionReporter(msg.sender, signal.target);
        }
        if (signal.status != Status.Confirmed) {
            revert InvalidExecutionStatus(signal.status);
        }
        if (executions[reportId].recorded) {
            revert ExecutionAlreadyRecorded(reportId);
        }

        executions[reportId] = ExecutionRecord({
            recorded: true,
            executor: executor,
            actionId: actionId,
            restrictionId: restrictionId,
            resultHash: resultHash
        });

        emit SignalExecutionRecorded(reportId, signal.target, executor, actionId, restrictionId, resultHash);
    }

    function getSignal(bytes32 reportId) external view returns (Signal memory signal) {
        return signals[reportId];
    }

    function getResolution(bytes32 reportId) external view returns (ResolutionMetadata memory resolution) {
        return resolutions[reportId];
    }

    function getExecution(bytes32 reportId) external view returns (ExecutionRecord memory execution) {
        return executions[reportId];
    }
}
