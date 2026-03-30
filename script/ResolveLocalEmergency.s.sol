// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {console2} from "forge-std/console2.sol";
import {Script} from "forge-std/Script.sol";

import {SafeVault4626} from "../src/SafeVault4626.sol";

contract ResolveLocalEmergency is Script {
    function run() external {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address vaultAddress = vm.envAddress("VAULT");
        string memory recoveryReason = vm.envOr("RECOVERY_REASON", string("peg restored locally"));

        vm.startBroadcast(privateKey);
        SafeVault4626(vaultAddress).resolveLocalEmergency(recoveryReason);
        vm.stopBroadcast();

        console2.log("vault", vaultAddress);
        console2.log("recoveryReason", recoveryReason);
    }
}
