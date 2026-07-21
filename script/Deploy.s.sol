// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {LauncherFactory} from "../src/LauncherFactory.sol";

/// @notice Deploys LauncherFactory pointed at $HOODIE.
/// Usage:
///   export HOODIE_ADDRESS=0xC72c01AAB5f5678dc1d6f5C6d2B417d91D402Ba3
///   export PRIVATE_KEY=0x<your_key>
///   forge script script/Deploy.s.sol --rpc-url robinhood_testnet --broadcast
contract Deploy is Script {
    function run() external returns (LauncherFactory factory) {
        address hoodie = vm.envAddress("HOODIE_ADDRESS");
        uint256 pk = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(pk);
        factory = new LauncherFactory(hoodie);
        console.log("LauncherFactory deployed at:", address(factory));
        vm.stopBroadcast();
    }
}
