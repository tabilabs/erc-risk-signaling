// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";

import {MockAdjudicator} from "../src/MockAdjudicator.sol";
import {MockExecutor} from "../src/MockExecutor.sol";

contract RunDepegScenario is Script {
    error MissingReportId();
    error NoActionRequested();

    /// @dev Pure guard validation, callable from tests without vm.setEnv dependency.
    function validateInputs(bytes32 reportId, bool skipConfirmation, bool triggerExecution) public pure {
        if (reportId == bytes32(0)) {
            revert MissingReportId();
        }
        if (skipConfirmation && !triggerExecution) {
            revert NoActionRequested();
        }
    }

    function run() external {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        bytes32 reportId = vm.envBytes32("REPORT_ID");
        address registryAddress = vm.envAddress("REGISTRY");
        address adjudicatorAddress = vm.envAddress("ADJUDICATOR");
        address executorAddress = vm.envAddress("EXECUTOR");
        address vaultAddress = vm.envAddress("VAULT");
        bytes32 resolutionHash = vm.envBytes32("RESOLUTION_HASH");
        bool triggerExecution = vm.envOr("TRIGGER_EXECUTION", true);
        bool skipConfirmation = vm.envOr("SKIP_CONFIRMATION", false);

        validateInputs(reportId, skipConfirmation, triggerExecution);

        vm.startBroadcast(privateKey);

        if (!skipConfirmation) {
            MockAdjudicator(adjudicatorAddress).confirm(reportId, resolutionHash);
        }
        if (triggerExecution) {
            MockExecutor(executorAddress).trigger(vaultAddress, registryAddress, reportId);
            // A consumer or indexer can read the responder snapshot here and combine it with resultHash
            // as a post-execution local state anchor, rather than assuming a generic state-diff proof.
        }

        vm.stopBroadcast();
    }
}
