// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {LeashFactory} from "../src/LeashFactory.sol";
import {LeashWallet} from "../src/LeashWallet.sol";
import {MockERC20} from "../src/MockERC20.sol";

/// Owner step of the live demo: token + wallet + policy + gas top-ups for the two other roles.
/// env: FACTORY, AGENT, WORKER (addresses). Run with --private-key <owner>.
contract MainnetSetup is Script {
    function run() external {
        address agent = vm.envAddress("AGENT");
        address worker = vm.envAddress("WORKER");
        LeashFactory f = LeashFactory(vm.envAddress("FACTORY"));
        vm.startBroadcast();
        MockERC20 t = new MockERC20("Leash Demo Dollar", "lUSD", 6); // worthless demo token, NOT a stablecoin
        LeashWallet w = f.createWallet(agent);
        t.mint(address(w), 100e6);
        w.setTokenPolicy(address(t), true, 25e6, 60e6);
        w.setPayee(worker, true);
        payable(agent).transfer(0.12 ether);
        payable(worker).transfer(0.08 ether);
        vm.stopBroadcast();
        console2.log("token", address(t));
        console2.log("wallet", address(w));
    }
}
