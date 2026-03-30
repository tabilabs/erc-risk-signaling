// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

interface IProtocolResponder is IERC165 {
    function getSupportedActions() external view returns (bytes32[] memory actionIds);

    function getActiveRestrictions() external view returns (bytes32[] memory restrictionIds);
}
