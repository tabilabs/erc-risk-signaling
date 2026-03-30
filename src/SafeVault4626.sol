// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import {IRiskRegistry} from "./interfaces/IRiskRegistry.sol";
import {IProtocolResponder} from "./interfaces/IProtocolResponder.sol";
import {IProtocolResponseExecutor} from "./interfaces/IProtocolResponseExecutor.sol";
import {IProtocolResponseHelper} from "./interfaces/IProtocolResponseHelper.sol";
import {RiskResponseCodes} from "./libraries/RiskResponseCodes.sol";

contract SafeVault4626 is ERC4626, Ownable, ERC165, IProtocolResponder, IProtocolResponseExecutor, IProtocolResponseHelper {
    mapping(bytes32 => bool) public processedReports;

    address public override trustedRiskRegistry;
    bool public depositPaused;
    bytes32 public activeReportId;

    error UnsupportedSignal(bytes32 reportId);
    error ReportNotConfirmed(bytes32 reportId);
    error ReportAlreadyProcessed(bytes32 reportId);
    error UntrustedRegistry(address provided, address expected);

    constructor(IERC20 asset_, address initialOwner)
        ERC4626(asset_)
        ERC20("Safe Vault Share", "svSHARE")
        Ownable(initialOwner)
    {}

    function supportsInterface(bytes4 interfaceId) public view override(ERC165, IERC165) returns (bool) {
        return interfaceId == type(IProtocolResponder).interfaceId
            || interfaceId == type(IProtocolResponseExecutor).interfaceId
            || interfaceId == type(IProtocolResponseHelper).interfaceId || super.supportsInterface(interfaceId);
    }

    function emergencyStatus() external view returns (bool isActive, bytes32 currentReportId) {
        return (depositPaused, activeReportId);
    }

    function setTrustedRiskRegistry(address newTrustedRegistry) external onlyOwner {
        address previousRegistry = trustedRiskRegistry;
        trustedRiskRegistry = newTrustedRegistry;

        emit TrustedRiskRegistryUpdated(msg.sender, previousRegistry, newTrustedRegistry);
    }

    function getSupportedActions() external pure returns (bytes32[] memory actionIds) {
        actionIds = new bytes32[](1);
        actionIds[0] = RiskResponseCodes.ACTION_PAUSE_DEPOSIT;
    }

    function getActiveRestrictions() external view returns (bytes32[] memory restrictionIds) {
        if (!depositPaused) {
            return new bytes32[](0);
        }

        restrictionIds = new bytes32[](1);
        restrictionIds[0] = RiskResponseCodes.RESTRICTION_PAUSE_DEPOSIT;
    }

    function triggerEmergencyAction(address registry, bytes32 reportId) external {
        if (registry != trustedRiskRegistry) {
            revert UntrustedRegistry(registry, trustedRiskRegistry);
        }
        if (processedReports[reportId]) {
            revert ReportAlreadyProcessed(reportId);
        }

        IRiskRegistry.Signal memory signal = IRiskRegistry(registry).getSignal(reportId);
        if (signal.target != address(this)) {
            revert UnsupportedSignal(reportId);
        }
        if (signal.status != IRiskRegistry.Status.Confirmed) {
            revert ReportNotConfirmed(reportId);
        }

        processedReports[reportId] = true;
        depositPaused = true;
        activeReportId = reportId;

        // Anchor the post-execution local state; this PoC does not attempt to encode a state diff proof.
        bytes32 resultHash = _executionSnapshotHash();
        IRiskRegistry(registry)
            .recordExecution(
                reportId,
                msg.sender,
                RiskResponseCodes.ACTION_PAUSE_DEPOSIT,
                RiskResponseCodes.RESTRICTION_PAUSE_DEPOSIT,
                resultHash
            );

        emit EmergencyActionExecuted(
            reportId,
            registry,
            msg.sender,
            RiskResponseCodes.ACTION_PAUSE_DEPOSIT,
            RiskResponseCodes.RESTRICTION_PAUSE_DEPOSIT,
            resultHash
        );
    }

    function resolveLocalEmergency(string calldata reason) external onlyOwner {
        bytes32 resolvedReportId = activeReportId;
        bytes32 clearedRestrictionId = depositPaused ? RiskResponseCodes.RESTRICTION_PAUSE_DEPOSIT : bytes32(0);
        depositPaused = false;
        activeReportId = bytes32(0);

        emit LocalEmergencyResolved(msg.sender, resolvedReportId, clearedRestrictionId, reason);
    }

    function maxDeposit(address) public view override returns (uint256) {
        if (depositPaused) {
            return 0;
        }

        return type(uint256).max;
    }

    function maxMint(address) public view override returns (uint256) {
        if (depositPaused) {
            return 0;
        }

        return type(uint256).max;
    }

    function _executionSnapshotHash() internal view returns (bytes32) {
        return keccak256(
            abi.encode(
                RiskResponseCodes.ACTION_PAUSE_DEPOSIT,
                RiskResponseCodes.RESTRICTION_PAUSE_DEPOSIT,
                depositPaused,
                activeReportId
            )
        );
    }
}
