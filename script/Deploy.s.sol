// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {LeashFactory} from "../src/LeashFactory.sol";

/// forge script script/Deploy.s.sol --rpc-url hashkey_mainnet --private-key $PK --broadcast
contract Deploy is Script {
    function run() external {
        vm.startBroadcast();
        LeashFactory f = new LeashFactory();
        vm.stopBroadcast();
        console2.log("LeashFactory", address(f));
    }
}
