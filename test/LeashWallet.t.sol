// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {LeashWallet} from "../src/LeashWallet.sol";
import {LeashFactory} from "../src/LeashFactory.sol";
import {MockERC20} from "../src/MockERC20.sol";

contract LeashWalletTest is Test {
    LeashWallet w;
    MockERC20 usdc;
    address owner = address(0xA11CE);
    address agent = address(0xA6E47);
    address worker = address(0xB0B);
    address stranger = address(0xBAD);
    bytes32 constant TASK = keccak256("summarise 10 filings");
    bytes32 constant DELIV = keccak256("summary.md");

    function setUp() public {
        usdc = new MockERC20("USDC", "USDC", 6);
        LeashFactory f = new LeashFactory();
        vm.prank(owner);
        w = f.createWallet(agent);
        usdc.mint(address(w), 1_000e6);
        vm.startPrank(owner);
        w.setTokenPolicy(address(usdc), true, 100e6, 250e6);
        w.setPayee(worker, true);
        vm.stopPrank();
    }

    function _hire(uint128 amt) internal returns (uint256) {
        vm.prank(agent);
        return w.hire(worker, address(usdc), amt, uint64(block.timestamp + 1 days), TASK);
    }

    function test_happyPath() public {
        uint256 id = _hire(80e6);
        assertEq(w.reserved(address(usdc)), 80e6);
        vm.prank(worker);
        w.deliver(id, DELIV);
        vm.prank(agent);
        w.approve(id);
        assertEq(usdc.balanceOf(worker), 80e6);
        assertEq(w.reserved(address(usdc)), 0);
        assertEq(uint8(w.getJob(id).status), uint8(LeashWallet.Status.Released));
        assertTrue(w.logHead() != bytes32(0));
    }

    function test_agentCannotWithdrawOrConfigure() public {
        vm.startPrank(agent);
        vm.expectRevert(LeashWallet.NotOwner.selector);
        w.withdraw(address(usdc), agent, 1);
        vm.expectRevert(LeashWallet.NotOwner.selector);
        w.setPayee(stranger, true);
        vm.expectRevert(LeashWallet.NotOwner.selector);
        w.setTokenPolicy(address(usdc), true, type(uint128).max, type(uint128).max);
        vm.stopPrank();
    }

    function test_strangerCannotHire() public {
        vm.prank(stranger);
        vm.expectRevert(LeashWallet.NotAgent.selector);
        w.hire(worker, address(usdc), 1e6, uint64(block.timestamp + 1 hours), TASK);
    }

    function test_payeeAllowlist() public {
        vm.prank(agent);
        vm.expectRevert(LeashWallet.PayeeNotAllowed.selector);
        w.hire(stranger, address(usdc), 1e6, uint64(block.timestamp + 1 hours), TASK);
    }

    function test_perJobCap() public {
        vm.prank(agent);
        vm.expectRevert(LeashWallet.OverPerJobCap.selector);
        w.hire(worker, address(usdc), 101e6, uint64(block.timestamp + 1 hours), TASK);
    }

    function test_dailyCapAndWindowReset() public {
        _hire(100e6);
        _hire(100e6);
        _hire(50e6); // 250 used
        vm.prank(agent);
        vm.expectRevert(LeashWallet.OverDailyCap.selector);
        w.hire(worker, address(usdc), 1e6, uint64(block.timestamp + 1 hours), TASK);
        vm.warp(block.timestamp + 1 days + 1);
        _hire(100e6); // new window
    }

    function test_tokenNotEnabled() public {
        MockERC20 other = new MockERC20("X", "X", 6);
        other.mint(address(w), 10e6);
        vm.prank(agent);
        vm.expectRevert(LeashWallet.TokenNotEnabled.selector);
        w.hire(worker, address(other), 1e6, uint64(block.timestamp + 1 hours), TASK);
    }

    function test_deadlineBounds() public {
        vm.startPrank(agent);
        vm.expectRevert(LeashWallet.BadDeadline.selector);
        w.hire(worker, address(usdc), 1e6, uint64(block.timestamp), TASK);
        vm.expectRevert(LeashWallet.BadDeadline.selector);
        w.hire(worker, address(usdc), 1e6, uint64(block.timestamp + 4 days), TASK);
        vm.stopPrank();
    }

    function test_ownerCannotWithdrawEscrow() public {
        _hire(100e6);
        vm.prank(owner);
        vm.expectRevert(LeashWallet.InsufficientFree.selector);
        w.withdraw(address(usdc), owner, 901e6);
        vm.prank(owner);
        w.withdraw(address(usdc), owner, 900e6);
        assertEq(usdc.balanceOf(address(w)), 100e6);
    }

    function test_cannotHireBeyondFreeBalance() public {
        vm.prank(owner);
        w.withdraw(address(usdc), owner, 950e6);
        vm.prank(agent);
        vm.expectRevert(LeashWallet.InsufficientFree.selector);
        w.hire(worker, address(usdc), 60e6, uint64(block.timestamp + 1 hours), TASK);
    }

    function test_timeoutRefund() public {
        uint256 id = _hire(50e6);
        vm.expectRevert(LeashWallet.TooEarly.selector);
        w.refund(id);
        vm.warp(block.timestamp + 1 days + 1);
        vm.prank(worker);
        vm.expectRevert(LeashWallet.TooLate.selector);
        w.deliver(id, DELIV);
        vm.prank(stranger);
        w.refund(id);
        assertEq(w.reserved(address(usdc)), 0);
        assertEq(usdc.balanceOf(address(w)), 1_000e6);
    }

    function test_autoRelease_ifAgentSilent() public {
        uint256 id = _hire(50e6);
        vm.prank(worker);
        w.deliver(id, DELIV);
        vm.expectRevert(LeashWallet.TooEarly.selector);
        w.release(id);
        vm.warp(block.timestamp + 1 days);
        vm.prank(stranger);
        w.release(id);
        assertEq(usdc.balanceOf(worker), 50e6);
    }

    function test_disputeThenResolveSplit() public {
        uint256 id = _hire(100e6);
        vm.prank(worker);
        w.deliver(id, DELIV);
        vm.prank(agent);
        w.dispute(id);
        vm.prank(owner);
        w.resolve(id, 3000);
        assertEq(usdc.balanceOf(worker), 30e6);
        assertEq(w.reserved(address(usdc)), 0);
        assertEq(usdc.balanceOf(address(w)), 970e6);
    }

    function test_disputeTimeoutPaysPayee() public {
        uint256 id = _hire(100e6);
        vm.prank(worker);
        w.deliver(id, DELIV);
        vm.prank(agent);
        w.dispute(id);
        vm.warp(block.timestamp + 1 days + 7 days - 1);
        vm.expectRevert(LeashWallet.TooEarly.selector);
        w.release(id);
        vm.warp(block.timestamp + 1);
        w.release(id);
        assertEq(usdc.balanceOf(worker), 100e6);
    }

    function test_cannotDisputeAfterWindow() public {
        uint256 id = _hire(10e6);
        vm.prank(worker);
        w.deliver(id, DELIV);
        vm.warp(block.timestamp + 1 days);
        vm.prank(agent);
        vm.expectRevert(LeashWallet.TooLate.selector);
        w.dispute(id);
    }

    function test_pauseBlocksHireNotSettlement() public {
        uint256 id = _hire(10e6);
        vm.prank(owner);
        w.setPaused(true);
        vm.prank(agent);
        vm.expectRevert(LeashWallet.Paused.selector);
        w.hire(worker, address(usdc), 1e6, uint64(block.timestamp + 1 hours), TASK);
        vm.prank(worker);
        w.deliver(id, DELIV); // in-flight work still settles
        vm.prank(owner);
        w.approve(id);
        assertEq(usdc.balanceOf(worker), 10e6);
    }

    function test_onlyPayeeDelivers_noDoubleSettle() public {
        uint256 id = _hire(10e6);
        vm.prank(stranger);
        vm.expectRevert(LeashWallet.NotPayee.selector);
        w.deliver(id, DELIV);
        vm.prank(worker);
        w.deliver(id, DELIV);
        vm.prank(agent);
        w.approve(id);
        vm.prank(agent);
        vm.expectRevert(LeashWallet.BadState.selector);
        w.approve(id);
        vm.expectRevert(LeashWallet.BadState.selector);
        w.release(id);
    }

    function test_receiptChainChanges() public {
        bytes32 h0 = w.logHead();
        uint256 id = _hire(10e6);
        bytes32 h1 = w.logHead();
        vm.prank(worker);
        w.deliver(id, DELIV);
        bytes32 h2 = w.logHead();
        assertTrue(h0 != h1 && h1 != h2);
    }

    /// invariant-style fuzz: whatever the agent does, the owner can always withdraw (balance - reserved) and escrow stays solvent.
    function testFuzz_solvency(uint128 a1, uint128 a2, bool deliver1) public {
        a1 = uint128(bound(a1, 1, 100e6));
        a2 = uint128(bound(a2, 1, 100e6));
        uint256 i1 = _hire(a1);
        _hire(a2);
        if (deliver1) {
            vm.prank(worker);
            w.deliver(i1, DELIV);
            vm.prank(agent);
            w.approve(i1);
        }
        assertGe(usdc.balanceOf(address(w)), w.reserved(address(usdc)));
        uint256 free = w.freeBalance(address(usdc));
        vm.prank(owner);
        w.withdraw(address(usdc), owner, free);
        assertEq(usdc.balanceOf(address(w)), w.reserved(address(usdc)));
    }
}
