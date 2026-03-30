// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

import {IProtocolResponder} from "./interfaces/IProtocolResponder.sol";

contract MockExecutor {
    event ExecutionTriggered(
        address indexed responder, address indexed registry, bytes32 indexed reportId, address caller
    );

    function trigger(address responder, address registry, bytes32 reportId) external {
        IProtocolResponder(responder).triggerEmergencyAction(registry, reportId);
        emit ExecutionTriggered(responder, registry, reportId, msg.sender);
    }
}
