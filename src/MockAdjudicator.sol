// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {IRiskRegistry} from "./interfaces/IRiskRegistry.sol";
import {MockRiskRegistry} from "./MockRiskRegistry.sol";

contract MockAdjudicator is Ownable {
    MockRiskRegistry public immutable REGISTRY;

    constructor(MockRiskRegistry registry_, address initialOwner) Ownable(initialOwner) {
        REGISTRY = registry_;
    }

    function confirm(bytes32 reportId, bytes32 resolutionHash) external onlyOwner {
        REGISTRY.resolveSignal(
            reportId,
            IRiskRegistry.Status.Confirmed,
            IRiskRegistry.ResolutionMetadata({adjudicator: address(this), resolutionHash: resolutionHash})
        );
    }

    function reject(bytes32 reportId, bytes32 resolutionHash) external onlyOwner {
        REGISTRY.resolveSignal(
            reportId,
            IRiskRegistry.Status.Rejected,
            IRiskRegistry.ResolutionMetadata({adjudicator: address(this), resolutionHash: resolutionHash})
        );
    }
}
