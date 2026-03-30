// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {IRiskRegistry} from "../src/interfaces/IRiskRegistry.sol";
import {MockAdjudicator} from "../src/MockAdjudicator.sol";
import {MockExecutor} from "../src/MockExecutor.sol";
import {MockRiskRegistry} from "../src/MockRiskRegistry.sol";
import {MockUSDC} from "../src/MockUSDC.sol";
import {RiskResponseCodes} from "../src/libraries/RiskResponseCodes.sol";
import {RiskStateLens} from "../src/RiskStateLens.sol";
import {SafeVault4626} from "../src/SafeVault4626.sol";

contract RiskStateLensTest is Test {
    address internal admin = makeAddr("admin");
    address internal whitehat = makeAddr("whitehat");
    address internal user = makeAddr("user");

    MockUSDC internal asset;
    MockRiskRegistry internal registry;
    MockAdjudicator internal adjudicator;
    MockExecutor internal executor;
    SafeVault4626 internal vault;
    RiskStateLens internal lens;

    function setUp() public {
        asset = new MockUSDC();
        registry = new MockRiskRegistry(0.1 ether, admin);
        adjudicator = new MockAdjudicator(registry, admin);
        executor = new MockExecutor();
        vault = new SafeVault4626(asset, admin);
        lens = new RiskStateLens();

        vm.prank(admin);
        registry.transferOwnership(address(adjudicator));
        vm.prank(admin);
        vault.setTrustedRiskRegistry(address(registry));

        asset.mint(user, 1_000_000e6);
        vm.prank(user);
        asset.approve(address(vault), type(uint256).max);
        vm.prank(user);
        vault.deposit(100e6, user);
    }

    function testLensDistinguishesConfirmedFromExecutionRecord() public {
        bytes32 reportId = _raiseAndConfirm(address(vault));

        RiskStateLens.Snapshot memory beforeExecution = lens.snapshot(address(registry), address(vault), reportId);
        assertEq(uint256(beforeExecution.registryStatus), uint256(IRiskRegistry.Status.Confirmed));
        assertEq(beforeExecution.target, address(vault));
        assertEq(beforeExecution.targetType, RiskResponseCodes.TARGET_TYPE_VAULT);
        assertEq(beforeExecution.riskType, RiskResponseCodes.RISK_DEPEG);
        assertFalse(beforeExecution.hasExecutionRecord);
        assertFalse(beforeExecution.isEmergencyActive);
        assertEq(beforeExecution.activeReportId, bytes32(0));
        assertEq(beforeExecution.restrictionIds.length, 0);
        assertFalse(beforeExecution.isExecutionConsistent);

        executor.trigger(address(vault), address(registry), reportId);

        RiskStateLens.Snapshot memory afterExecution = lens.snapshot(address(registry), address(vault), reportId);
        assertEq(uint256(afterExecution.registryStatus), uint256(IRiskRegistry.Status.Confirmed));
        assertTrue(afterExecution.hasExecutionRecord);
        assertTrue(afterExecution.isEmergencyActive);
        assertEq(afterExecution.activeReportId, reportId);
        assertEq(afterExecution.restrictionIds.length, 1);
        assertEq(afterExecution.restrictionIds[0], RiskResponseCodes.RESTRICTION_PAUSE_DEPOSIT);
        assertTrue(afterExecution.isExecutionConsistent);
    }

    function testLensShowsLocalRecoveryBreaksExecutionConsistency() public {
        bytes32 reportId = _raiseAndConfirm(address(vault));
        executor.trigger(address(vault), address(registry), reportId);

        vm.prank(admin);
        vault.resolveLocalEmergency("peg restored locally");

        RiskStateLens.Snapshot memory afterLocalRecovery = lens.snapshot(address(registry), address(vault), reportId);
        assertEq(uint256(afterLocalRecovery.registryStatus), uint256(IRiskRegistry.Status.Confirmed));
        assertTrue(afterLocalRecovery.hasExecutionRecord);
        assertFalse(afterLocalRecovery.isEmergencyActive);
        assertEq(afterLocalRecovery.activeReportId, bytes32(0));
        assertEq(afterLocalRecovery.restrictionIds.length, 0);
        assertFalse(afterLocalRecovery.isExecutionConsistent);
    }

    function _raiseAndConfirm(address target) internal returns (bytes32 reportId) {
        vm.deal(whitehat, 1 ether);

        vm.prank(whitehat);
        reportId = registry.raiseSignal{value: 0.1 ether}(
            target,
            RiskResponseCodes.TARGET_TYPE_VAULT,
            RiskResponseCodes.RISK_DEPEG,
            3,
            bytes32(0),
            abi.encodePacked("evidence:slow-depeg")
        );

        vm.prank(admin);
        adjudicator.confirm(reportId, keccak256("confirmed:slow-depeg"));
    }
}
