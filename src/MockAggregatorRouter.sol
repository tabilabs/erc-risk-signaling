// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import {RiskAwareConsumerLens} from "./RiskAwareConsumerLens.sol";

contract MockAggregatorRouter {
    error InputLengthMismatch();
    error NoRouteAvailable();

    RiskAwareConsumerLens public immutable CONSUMER_LENS;

    constructor(RiskAwareConsumerLens consumerLens_) {
        CONSUMER_LENS = consumerLens_;
    }

    function getRouteDecision(address registry, address vault, bytes32 reportId)
        public
        view
        returns (RiskAwareConsumerLens.Decision memory)
    {
        return CONSUMER_LENS.decision(registry, vault, reportId);
    }

    function shouldSkipVault(address registry, address vault, bytes32 reportId) public view returns (bool) {
        return getRouteDecision(registry, vault, reportId).shouldSkipVault;
    }

    function selectDepositRoute(address registry, address[] calldata vaults, bytes32[] calldata reportIds)
        external
        view
        returns (address selectedVault)
    {
        if (vaults.length != reportIds.length) {
            revert InputLengthMismatch();
        }

        for (uint256 i = 0; i < vaults.length; ++i) {
            if (!shouldSkipVault(registry, vaults[i], reportIds[i])) {
                return vaults[i];
            }
        }

        revert NoRouteAvailable();
    }

    function canRouteExit(address registry, address vault, bytes32 reportId, address owner, uint256 shares)
        external
        view
        returns (bool)
    {
        RiskAwareConsumerLens.Decision memory routeDecision = getRouteDecision(registry, vault, reportId);
        // The current PoC always allows exit, but the guard stays here so future responders can narrow exits explicitly.
        return routeDecision.shouldAllowExit && IERC4626(vault).maxRedeem(owner) >= shares;
    }
}
