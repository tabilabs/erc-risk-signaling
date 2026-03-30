// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {console2} from "forge-std/console2.sol";
import {Script} from "forge-std/Script.sol";

import {MockUSDC} from "../src/MockUSDC.sol";
import {SafeVault4626} from "../src/SafeVault4626.sol";

contract SeedDemoPosition is Script {
    error ZeroDepositAmount();

    function run() external returns (uint256 mintedShares) {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address assetAddress = vm.envAddress("ASSET");
        address vaultAddress = vm.envAddress("VAULT");
        uint256 depositAmount = vm.envOr("DEPOSIT_AMOUNT", uint256(100e6));
        address owner = vm.addr(privateKey);

        if (depositAmount == 0) {
            revert ZeroDepositAmount();
        }

        vm.startBroadcast(privateKey);
        MockUSDC asset = MockUSDC(assetAddress);
        asset.mint(owner, depositAmount);
        asset.approve(vaultAddress, depositAmount);
        mintedShares = SafeVault4626(vaultAddress).deposit(depositAmount, owner);
        vm.stopBroadcast();

        console2.log("owner", owner);
        console2.log("vault", vaultAddress);
        console2.log("depositAmount", depositAmount);
        console2.log("mintedShares", mintedShares);
    }
}
