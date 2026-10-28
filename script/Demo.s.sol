// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {LeashFactory} from "../src/LeashFactory.sol";
import {LeashWallet} from "../src/LeashWallet.sol";
import {MockERC20} from "../src/MockERC20.sol";

/// Local/testnet demo of the full A2A lifecycle with three roles (owner, agent, worker). Uses a mock stablecoin.
/// env: OWNER_PK, AGENT_PK, WORKER_PK
contract Demo is Script {
    function run() external {
        uint256 opk = vm.envUint("OWNER_PK");
        uint256 apk = vm.envUint("AGENT_PK");
        uint256 wpk = vm.envUint("WORKER_PK");
        address agent = vm.addr(apk);
        address worker = vm.addr(wpk);

        vm.startBroadcast(opk);
        MockERC20 usdc = new MockERC20("Mock USDC", "mUSDC", 6);
        LeashFactory f = new LeashFactory();
        LeashWallet w = f.createWallet(agent);
        usdc.mint(address(w), 500e6);
        w.setTokenPolicy(address(usdc), true, 50e6, 120e6); // <=50/job, <=120/day
        w.setPayee(worker, true);
        vm.stopBroadcast();

        // job 1: delivered + approved
        vm.startBroadcast(apk);
        uint256 j1 = w.hire(worker, address(usdc), 40e6, uint64(block.timestamp + 1 days), keccak256("translate whitepaper"));
        vm.stopBroadcast();
        vm.startBroadcast(wpk);
        w.deliver(j1, keccak256("whitepaper_zh.md"));
        vm.stopBroadcast();
        vm.startBroadcast(apk);
        w.approve(j1);
        // job 2: delivered then disputed, owner splits 25/75
        uint256 j2 = w.hire(worker, address(usdc), 50e6, uint64(block.timestamp + 1 days), keccak256("label 1k images"));
        vm.stopBroadcast();
        vm.startBroadcast(wpk);
        w.deliver(j2, keccak256("labels.csv"));
        vm.stopBroadcast();
        vm.startBroadcast(apk);
        w.dispute(j2);
        vm.stopBroadcast();
        vm.startBroadcast(opk);
        w.resolve(j2, 2500);
        vm.stopBroadcast();

        console2.log("wallet", address(w));
        console2.log("token", address(usdc));
        console2.log("logHead");
        console2.logBytes32(w.logHead());
    }
}
