// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

interface IProtocolResponseHelper is IERC165 {
    event TrustedRiskRegistryUpdated(
        address indexed updatedBy, address indexed previousRegistry, address indexed newRegistry
    );
    event LocalEmergencyResolved(
        address indexed resolvedBy,
        bytes32 indexed previousReportId,
        bytes32 indexed clearedRestrictionId,
        string reason
    );

    function emergencyStatus() external view returns (bool isActive, bytes32 activeReportId);

    function trustedRiskRegistry() external view returns (address registry);

    function resolveLocalEmergency(string calldata reason) external;
}
