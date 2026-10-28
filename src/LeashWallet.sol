// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title LeashWallet
/// @notice A budget-bounded wallet for an AI agent that *hires other agents* (A2A settlement).
///         The agent key can only open escrowed jobs inside owner-set limits; it can never withdraw.
///         Payments to the hired agent are escrowed in this contract, released on delivery
///         (approve / auto-release) or refunded on timeout. Every state change is folded into a hash-chained receipt log.
contract LeashWallet {
    using SafeERC20 for IERC20;

    enum Status { None, Open, Delivered, Disputed, Released, Refunded, Resolved }

    struct TokenPolicy {
        bool enabled;
        uint128 perJobCap; // max amount of a single job
        uint128 dailyCap; // max newly-committed amount per rolling window (fixed 24h bucket)
        uint64 windowStart;
        uint128 spentInWindow;
    }

    struct Job {
        address payee;
        address token;
        uint128 amount;
        uint64 deadline; // payee must deliver by this time
        uint64 deliveredAt;
        Status status;
        bytes32 taskHash; // keccak256 of the task spec (published off-chain)
        bytes32 deliveryHash; // keccak256 of the deliverable
    }

    address public owner;
    address public agent;
    bool public paused;

    uint64 public maxJobDuration = 3 days;
    uint64 public reviewWindow = 1 days; // after delivery: agent/owner may approve or dispute; afterwards anyone may release
    uint64 public disputeTimeout = 7 days; // owner must resolve a dispute within this; afterwards payee may claim

    mapping(address => TokenPolicy) public policy;
    mapping(address => bool) public payeeAllowed;
    mapping(address => uint256) public reserved; // token => amount locked in open jobs
    Job[] private _jobs;
    bytes32 public logHead;

    event JobOpened(uint256 indexed jobId, address indexed payee, address indexed token, uint256 amount, uint64 deadline, bytes32 taskHash);
    event JobDelivered(uint256 indexed jobId, bytes32 deliveryHash);
    event JobSettled(uint256 indexed jobId, Status status, uint256 toPayee, uint256 refunded);
    event JobDisputed(uint256 indexed jobId);
    event Receipt(uint256 indexed jobId, bytes32 indexed newHead);
    event PolicySet(address indexed token, bool enabled, uint256 perJobCap, uint256 dailyCap);
    event PayeeSet(address indexed payee, bool allowed);
    event AgentSet(address indexed agent);
    event PausedSet(bool paused);
    event Withdrawn(address indexed token, address indexed to, uint256 amount);

    error NotOwner();
    error NotAgent();
    error NotPayee();
    error Paused();
    error PayeeNotAllowed();
    error TokenNotEnabled();
    error OverPerJobCap();
    error OverDailyCap();
    error BadDeadline();
    error InsufficientFree();
    error BadState();
    error TooEarly();
    error TooLate();
    error BadBps();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    modifier onlyAgentOrOwner() {
        if (msg.sender != agent && msg.sender != owner) revert NotAgent();
        _;
    }

    constructor(address owner_, address agent_) {
        owner = owner_;
        agent = agent_;
        emit AgentSet(agent_);
    }

    // ───────────────────────── owner: configuration ─────────────────────────

    function setAgent(address a) external onlyOwner {
        agent = a;
        emit AgentSet(a);
    }

    function setPaused(bool p) external onlyOwner {
        paused = p;
        emit PausedSet(p);
    }

    function setPayee(address payee, bool allowed) external onlyOwner {
        payeeAllowed[payee] = allowed;
        emit PayeeSet(payee, allowed);
    }

    function setTokenPolicy(address token, bool enabled, uint128 perJobCap, uint128 dailyCap) external onlyOwner {
        TokenPolicy storage p = policy[token];
        p.enabled = enabled;
        p.perJobCap = perJobCap;
        p.dailyCap = dailyCap;
        emit PolicySet(token, enabled, perJobCap, dailyCap);
    }

    function setTimings(uint64 maxJobDuration_, uint64 reviewWindow_, uint64 disputeTimeout_) external onlyOwner {
        maxJobDuration = maxJobDuration_;
        reviewWindow = reviewWindow_;
        disputeTimeout = disputeTimeout_;
    }

    /// @notice Owner can only withdraw funds NOT locked in open jobs; payees' escrow is untouchable.
    function withdraw(address token, address to, uint256 amount) external onlyOwner {
        if (IERC20(token).balanceOf(address(this)) < reserved[token] + amount) revert InsufficientFree();
        IERC20(token).safeTransfer(to, amount);
        emit Withdrawn(token, to, amount);
    }

    function transferOwnership(address newOwner) external onlyOwner {
        owner = newOwner;
    }

    // ───────────────────────── agent: spend inside the leash ─────────────────────────

    function hire(address payee, address token, uint128 amount, uint64 deadline, bytes32 taskHash)
        external
        returns (uint256 jobId)
    {
        if (msg.sender != agent) revert NotAgent();
        if (paused) revert Paused();
        if (!payeeAllowed[payee]) revert PayeeNotAllowed();
        TokenPolicy storage p = policy[token];
        if (!p.enabled) revert TokenNotEnabled();
        if (amount == 0 || amount > p.perJobCap) revert OverPerJobCap();
        if (deadline <= block.timestamp || deadline > block.timestamp + maxJobDuration) revert BadDeadline();

        if (block.timestamp >= uint256(p.windowStart) + 1 days) {
            p.windowStart = uint64(block.timestamp);
            p.spentInWindow = 0;
        }
        if (uint256(p.spentInWindow) + amount > p.dailyCap) revert OverDailyCap();
        p.spentInWindow += amount;

        if (IERC20(token).balanceOf(address(this)) < reserved[token] + amount) revert InsufficientFree();
        reserved[token] += amount;

        jobId = _jobs.length;
        _jobs.push(Job(payee, token, amount, deadline, 0, Status.Open, taskHash, bytes32(0)));
        emit JobOpened(jobId, payee, token, amount, deadline, taskHash);
        _log(jobId, Status.Open, payee, token, amount, taskHash);
    }

    function approve(uint256 jobId) external onlyAgentOrOwner {
        Job storage j = _jobs[jobId];
        if (j.status != Status.Delivered) revert BadState();
        _pay(jobId, j, j.amount, Status.Released);
    }

    function dispute(uint256 jobId) external onlyAgentOrOwner {
        Job storage j = _jobs[jobId];
        if (j.status != Status.Delivered) revert BadState();
        if (block.timestamp >= uint256(j.deliveredAt) + reviewWindow) revert TooLate();
        j.status = Status.Disputed;
        emit JobDisputed(jobId);
        _log(jobId, Status.Disputed, j.payee, j.token, j.amount, j.deliveryHash);
    }

    /// @notice Owner splits a disputed job: `payeeBps`/10000 to the payee, rest back to the wallet.
    function resolve(uint256 jobId, uint16 payeeBps) external onlyOwner {
        Job storage j = _jobs[jobId];
        if (j.status != Status.Disputed) revert BadState();
        if (payeeBps > 10_000) revert BadBps();
        _pay(jobId, j, (uint256(j.amount) * payeeBps) / 10_000, Status.Resolved);
    }

    // ───────────────────────── payee ─────────────────────────

    function deliver(uint256 jobId, bytes32 deliveryHash) external {
        Job storage j = _jobs[jobId];
        if (msg.sender != j.payee) revert NotPayee();
        if (j.status != Status.Open) revert BadState();
        if (block.timestamp > j.deadline) revert TooLate();
        j.status = Status.Delivered;
        j.deliveredAt = uint64(block.timestamp);
        j.deliveryHash = deliveryHash;
        emit JobDelivered(jobId, deliveryHash);
        _log(jobId, Status.Delivered, j.payee, j.token, j.amount, deliveryHash);
    }

    // ───────────────────────── permissionless liveness ─────────────────────────

    /// @notice Anyone: pay the payee if the agent neither approved nor disputed in time
    ///         (or if the owner never resolved a dispute).
    function release(uint256 jobId) external {
        Job storage j = _jobs[jobId];
        if (j.status == Status.Delivered) {
            if (block.timestamp < uint256(j.deliveredAt) + reviewWindow) revert TooEarly();
        } else if (j.status == Status.Disputed) {
            if (block.timestamp < uint256(j.deliveredAt) + reviewWindow + disputeTimeout) revert TooEarly();
        } else {
            revert BadState();
        }
        _pay(jobId, j, j.amount, Status.Released);
    }

    /// @notice Anyone: if the payee missed the deadline, unlock the escrow back to the wallet.
    function refund(uint256 jobId) external {
        Job storage j = _jobs[jobId];
        if (j.status != Status.Open) revert BadState();
        if (block.timestamp <= j.deadline) revert TooEarly();
        _pay(jobId, j, 0, Status.Refunded);
    }

    // ───────────────────────── views ─────────────────────────

    function jobCount() external view returns (uint256) {
        return _jobs.length;
    }

    function getJob(uint256 jobId) external view returns (Job memory) {
        return _jobs[jobId];
    }

    function freeBalance(address token) external view returns (uint256) {
        uint256 b = IERC20(token).balanceOf(address(this));
        uint256 r = reserved[token];
        return b > r ? b - r : 0;
    }

    // ───────────────────────── internals ─────────────────────────

    function _pay(uint256 jobId, Job storage j, uint256 toPayee, Status end) internal {
        j.status = end;
        reserved[j.token] -= j.amount;
        if (toPayee > 0) IERC20(j.token).safeTransfer(j.payee, toPayee);
        emit JobSettled(jobId, end, toPayee, j.amount - toPayee);
        _log(jobId, end, j.payee, j.token, toPayee, j.deliveryHash);
    }

    function _log(uint256 jobId, Status s, address payee, address token, uint256 amount, bytes32 h) internal {
        logHead = keccak256(abi.encode(logHead, jobId, uint8(s), payee, token, amount, h));
        emit Receipt(jobId, logHead);
    }
}
