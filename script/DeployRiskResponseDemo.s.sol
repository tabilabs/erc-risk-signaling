// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {console2} from "forge-std/console2.sol";
import {Script} from "forge-std/Script.sol";

import {MockAdjudicator} from "../src/MockAdjudicator.sol";
import {MockAggregatorRouter} from "../src/MockAggregatorRouter.sol";
import {MockExecutor} from "../src/MockExecutor.sol";
import {MockRiskRegistry} from "../src/MockRiskRegistry.sol";
import {MockUSDC} from "../src/MockUSDC.sol";
import {RiskAwareConsumerLens} from "../src/RiskAwareConsumerLens.sol";
import {RiskStateLens} from "../src/RiskStateLens.sol";
import {SafeVault4626} from "../src/SafeVault4626.sol";

contract DeployRiskResponseDemo is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        MockUSDC asset = new MockUSDC();
        MockRiskRegistry registry = new MockRiskRegistry(0.1 ether, deployer);
        MockAdjudicator adjudicator = new MockAdjudicator(registry, deployer);
        MockExecutor executor = new MockExecutor();
        SafeVault4626 vault = new SafeVault4626(asset, deployer);
        SafeVault4626 safeVault = new SafeVault4626(asset, deployer);
        RiskStateLens lens = new RiskStateLens();
        RiskAwareConsumerLens consumer = new RiskAwareConsumerLens(lens);
        MockAggregatorRouter router = new MockAggregatorRouter(consumer);

        registry.transferOwnership(address(adjudicator));
        vault.setTrustedRiskRegistry(address(registry));
        safeVault.setTrustedRiskRegistry(address(registry));

        vm.stopBroadcast();

        console2.log("asset", address(asset));
        console2.log("registry", address(registry));
        console2.log("adjudicator", address(adjudicator));
        console2.log("executor", address(executor));
        console2.log("router", address(router));
        console2.log("vault", address(vault));
        console2.log("safeVault", address(safeVault));
        console2.log("vaultTrustedRegistry", vault.trustedRiskRegistry());
        console2.log("safeVaultTrustedRegistry", safeVault.trustedRiskRegistry());
        console2.log("lens", address(lens));
        console2.log("consumer", address(consumer));
    }
}
