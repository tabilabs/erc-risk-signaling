// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

import {console2} from "forge-std/console2.sol";
import {Script} from "forge-std/Script.sol";

import {MockAdjudicator} from "../src/MockAdjudicator.sol";

contract ResolveRegistrySignal is Script {
    error MissingReportId();

    function validateInputs(bytes32 reportId) public pure {
        if (reportId == bytes32(0)) {
            revert MissingReportId();
        }
    }

    function run() external {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address adjudicatorAddress = vm.envAddress("ADJUDICATOR");
        bytes32 reportId = vm.envBytes32("REPORT_ID");
        bytes32 resolutionHash = vm.envBytes32("REGISTRY_RESOLUTION_HASH");

        validateInputs(reportId);

        vm.startBroadcast(privateKey);
        MockAdjudicator(adjudicatorAddress).resolve(reportId, resolutionHash);
        vm.stopBroadcast();

        console2.log("adjudicator", adjudicatorAddress);
        console2.log("reportId");
        console2.logBytes32(reportId);
        console2.log("registryResolutionHash");
        console2.logBytes32(resolutionHash);
    }
}
