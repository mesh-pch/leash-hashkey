# Leash — a budget-bounded wallet for AI agents that hire other agents

> HashKey Chain Horizon Hackathon (Mumbai Edition) · **Agent Payments & A2A Settlement** track

When one AI agent pays another, someone has to hold the key. **Leash** puts the money in a contract where the
paying agent can *only* open escrowed jobs inside limits its human owner set — it can never withdraw — and the hired
agent is paid by the contract on delivery, not by anyone's goodwill.

```
 owner ── fund / policy / allowlist / pause / withdraw-free-funds ──▶ ┌────────────────────────┐
 (human, optionally funds via HSP checkout)                            │      LeashWallet        │
 agent key ── hire(payee, token, amount, deadline, taskHash) ───────▶ │ per-job cap · daily cap │──▶ payee (hired agent)
                                                                       │ payee allowlist         │     deliver(hash)
 payee ── deliver(deliveryHash) ──────────────────────────────────────▶ │ escrow · dispute · auto │
 anyone ── release() after review window · refund() after deadline ───▶ │ hash-chained receipts   │
                                                                       └────────────────────────┘
```

## Guarantees (all enforced in Solidity, all tested)
| Risk | Rule |
|---|---|
| Agent key stolen / model goes rogue | agent can only `hire`: allow-listed payees, enabled tokens, ≤ per-job cap, ≤ daily cap, ≤ 3-day deadline. No withdraw, no config. Worst case = daily cap. |
| Owner rugs a hired agent mid-job | escrowed funds are reserved: `withdraw` only touches *unreserved* balance. |
| Hired agent never delivers | after the deadline anyone calls `refund` → funds unlock. |
| Paying agent ghosts after delivery | after the review window anyone calls `release` → payee is paid. |
| Disputed work | agent/owner may `dispute` inside the review window; owner `resolve`s with a basis-point split; if the owner stalls past `disputeTimeout`, payee can claim. |
| "What did my agent buy?" | every state change is folded into a hash chain (`logHead`); `python/leash_verify.py` re-derives it from public events — any edit/omission → FAIL. |
| Emergency | `setPaused(true)` blocks new hires; in-flight jobs still settle. |

## Verify in one minute (or just run `python python/leash_verify.py https://mainnet.hsk.xyz 0xd3De0f08E2e9696AFB212BF55270f803A2F37a62 29409276` against mainnet)
```bash
git clone --recurse-submodules <this repo> && cd leash-hashkey
forge test                         # 19 tests incl. 256-run solvency fuzz
cd python && pip install eth-abi eth-hash pytest && pytest -q     # HSP adapter tests
# full lifecycle on a local chain, then re-derive the receipt chain from events:
anvil &                             # then:
OWNER_PK=.. AGENT_PK=.. WORKER_PK=.. forge script script/Demo.s.sol --rpc-url http://127.0.0.1:8545 --broadcast
python python/leash_verify.py http://127.0.0.1:8545 <wallet>      # -> OK: 7 receipts re-derived
```

## HSP (HashKey Settlement Platform)
`python/hsp_topup.py` builds a signed HSP merchant order that funds a LeashWallet (human treasury → agent wallet on-ramp).
**Status: signing + request shaping unit-tested; not yet exercised against the live HSP gateway** (merchant credentials required).

## Deploy
```bash
forge script script/Deploy.s.sol --rpc-url https://mainnet.hsk.xyz --private-key $PK --broadcast   # chain 177
```
**Live on HashKey Chain mainnet (177), source-verified on Blockscout:**
- LeashFactory [`0x8383854D98D0339D82F69d7bF9Baa69dbC559bcD`](https://hsk.blockscout.com/address/0x8383854D98D0339D82F69d7bF9Baa69dbC559bcD)
- Demo LeashWallet [`0xd3De0f08E2e9696AFB212BF55270f803A2F37a62`](https://hsk.blockscout.com/address/0xd3De0f08E2e9696AFB212BF55270f803A2F37a62) — one full hire → deliver → approve cycle executed, receipt chain re-verified from events.

All tx hashes in [DEPLOYMENTS.md](DEPLOYMENTS.md). The demo cycle uses a worthless demo token (lUSD), not a real stablecoin. Contracts are un-audited; use small limits.

MIT licensed.
