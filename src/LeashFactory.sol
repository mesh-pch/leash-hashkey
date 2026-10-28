// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {LeashWallet} from "./LeashWallet.sol";

/// @title LeashFactory — deploys LeashWallets and indexes them so dashboards/explorers can discover every leashed agent.
contract LeashFactory {
    event WalletCreated(address indexed owner, address indexed wallet, address indexed agent);

    address[] public allWallets;
    mapping(address => address[]) private _byOwner;

    function createWallet(address agent) external returns (LeashWallet w) {
        w = new LeashWallet(msg.sender, agent);
        allWallets.push(address(w));
        _byOwner[msg.sender].push(address(w));
        emit WalletCreated(msg.sender, address(w), agent);
    }

    function walletsOf(address owner) external view returns (address[] memory) {
        return _byOwner[owner];
    }

    function walletCount() external view returns (uint256) {
        return allWallets.length;
    }
}
