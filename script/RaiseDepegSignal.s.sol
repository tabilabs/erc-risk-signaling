// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {console2} from "forge-std/console2.sol";
import {Script} from "forge-std/Script.sol";

import {MockRiskRegistry} from "../src/MockRiskRegistry.sol";
import {RiskResponseCodes} from "../src/libraries/RiskResponseCodes.sol";

contract RaiseDepegSignal is Script {
    error SeverityTooHigh(uint256 provided);

    function run() external returns (bytes32 reportId) {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address registryAddress = vm.envAddress("REGISTRY");
        address target = vm.envAddress("TARGET");
        uint256 severity = vm.envOr("SEVERITY", uint256(3));
        bytes32 dependencyRef = vm.envOr("DEPENDENCY_REF", bytes32(0));
        string memory evidenceText = vm.envOr("EVIDENCE", string("evidence:slow-depeg"));

        MockRiskRegistry registry = MockRiskRegistry(registryAddress);
        uint256 bond = vm.envOr("BOND", registry.BOND_FLOOR());

        if (severity > type(uint8).max) {
            revert SeverityTooHigh(severity);
        }

        // Casting to uint8 is safe because severity is bounded above by type(uint8).max.
        // forge-lint: disable-next-line(unsafe-typecast)
        uint8 severity8 = uint8(severity);

        vm.startBroadcast(privateKey);
        reportId = registry.raiseSignal{value: bond}(
            target, RiskResponseCodes.RISK_DEPEG, severity8, dependencyRef, bytes(evidenceText)
        );
        vm.stopBroadcast();

        console2.log("target", target);
        console2.log("bond", bond);
        console2.log("severity", severity);
        console2.log("riskType");
        console2.logBytes32(RiskResponseCodes.RISK_DEPEG);
        console2.log("reportId");
        console2.logBytes32(reportId);
    }
}
