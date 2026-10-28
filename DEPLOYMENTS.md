# Deployments — HashKey Chain mainnet (chain id 177)

Explorer: https://hsk.blockscout.com · all three contracts are **source-verified** there.
Deployer / wallet owner: `0x1f47f871Cc8a9Eb90f38DfdcC1689C374500Bf70` · demo agent key: `0xE7bD08FabDC2147C60e52e70FeB898230B97D069` · demo worker (payee): `0xF9F4933925B6429102cB715F6Cbec72548fC75cd`

| Contract | Address | Tx |
|---|---|---|
| **LeashFactory** | [`0x8383854D98D0339D82F69d7bF9Baa69dbC559bcD`](https://hsk.blockscout.com/address/0x8383854D98D0339D82F69d7bF9Baa69dbC559bcD) | [`0x8ba8dde4…c1e1c1`](https://hsk.blockscout.com/tx/0x8ba8dde434eabeab2cec95e258d6561548da8f0d74f0c53ce9ba2305ecc1e1c1) |
| **LeashWallet** (demo, via factory) | [`0xd3De0f08E2e9696AFB212BF55270f803A2F37a62`](https://hsk.blockscout.com/address/0xd3De0f08E2e9696AFB212BF55270f803A2F37a62) | [`0x373c8950…49fd47`](https://hsk.blockscout.com/tx/0x373c8950039989976d3f0aad2e3e5f5cde485cd2384e0e410c1fdd008649fd47) |
| lUSD "Leash Demo Dollar" (worthless demo token, open mint) | [`0x65091B299B0F2F4642Bb5fA6119c67a8538B4b08`](https://hsk.blockscout.com/address/0x65091B299B0F2F4642Bb5fA6119c67a8538B4b08) | [`0xc094ee92…4fbba2`](https://hsk.blockscout.com/tx/0xc094ee92361c6ee59f200118643a0294c28477b2ce305a24f92a3f11a94fbba2) |

## Live A2A cycle on mainnet (agent hires worker, 20 lUSD, escrowed → delivered → approved → paid)
Policy set by owner: lUSD enabled, ≤25/job, ≤60/day, worker allow-listed (txs: [setTokenPolicy](https://hsk.blockscout.com/tx/0x52c4395a40eddd57d91fa36fc17ce73a3f68892c4a4c226f4cbfeebf0f0cdc3e), [setPayee](https://hsk.blockscout.com/tx/0xc0025643103a915c5cad33219cff9aad220881f4dfa1280285b1dda5659a3f57)).

| Step | Signer | Tx |
|---|---|---|
| `hire(worker, lUSD, 20, deadline, taskHash)` | agent | [`0x4189d6f8…ff4a`](https://hsk.blockscout.com/tx/0x4189d6f8b49c3ae5887de7f581d04419f4ab9b831b616b518fccee13ff50ff4a) |
| `deliver(0, deliveryHash)` | worker | [`0x75e09276…ff7f`](https://hsk.blockscout.com/tx/0x75e09276d37d7ba7b4bd46bd12ddead9baa85bc6e3436780c52b3c1e0625ff7f) |
| `approve(0)` → payout | agent | [`0xb83c3eeb…4e57`](https://hsk.blockscout.com/tx/0xb83c3eeb60dadda42885c41f5cac0ad51add4f040566a9d28e136f1eb01d4e57) |

On-chain `logHead` = `0xf4956130a6d693e6dd0a118df5b552f81fc82d456fb85f3caaa39d6b3b9cd8c4`. Reproduce:
```bash
python python/leash_verify.py https://mainnet.hsk.xyz 0xd3De0f08E2e9696AFB212BF55270f803A2F37a62 29409276
# OK: 3 receipts re-derived, head 0xf495…d8c4 == on-chain
```
Gas cost of the whole deployment + cycle ≈ 2.4 HSK (gas price is 500 gwei). No stablecoin was bought or bridged: the demo uses the worthless lUSD token above, so the cycle moves no real value.
