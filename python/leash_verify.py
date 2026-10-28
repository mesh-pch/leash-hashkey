"""Recompute a LeashWallet's hash-chained receipt log from public chain events and compare with on-chain logHead.

usage: python leash_verify.py <rpc_url> <wallet_address> [from_block]
Exit code 0 = every receipt re-derived and final head matches; 1 = mismatch (tampered / missing data).
"""
import json, sys, urllib.request
from eth_abi import encode, decode
from eth_hash.auto import keccak

STATUS = {"Open": 1, "Delivered": 2, "Disputed": 3, "Released": 4, "Refunded": 5, "Resolved": 6}


def topic(sig: str) -> str:
    return "0x" + keccak(sig.encode()).hex()


T_OPEN = topic("JobOpened(uint256,address,address,uint256,uint64,bytes32)")
T_DELIV = topic("JobDelivered(uint256,bytes32)")
T_SETTLED = topic("JobSettled(uint256,uint8,uint256,uint256)")
T_DISPUTED = topic("JobDisputed(uint256)")
T_RECEIPT = topic("Receipt(uint256,bytes32)")


def rpc(url, method, params):
    req = urllib.request.Request(url, json.dumps({"jsonrpc": "2.0", "id": 1, "method": method, "params": params}).encode(),
                                 {"content-type": "application/json", "user-agent": "leash-verify/1.0"})
    r = json.load(urllib.request.urlopen(req, timeout=30))
    if "error" in r:
        raise RuntimeError(r["error"])
    return r["result"]


def h(b: str) -> bytes:
    return bytes.fromhex(b[2:])


def addr(topic_hex: str) -> str:
    return "0x" + topic_hex[-40:]


def verify(url, wallet, from_block=0):
    logs = rpc(url, "eth_getLogs", [{"address": wallet, "fromBlock": hex(from_block), "toBlock": "latest"}])
    logs.sort(key=lambda l: (int(l["blockNumber"], 16), int(l["logIndex"], 16)))
    head = b"\x00" * 32
    jobs = {}  # jobId -> dict(payee, token, amount, deliveryHash)
    pending = None
    n = 0
    for l in logs:
        t0 = l["topics"][0]
        data = h(l["data"])
        if t0 == T_OPEN:
            jid = int(l["topics"][1], 16)
            amount, _deadline, task = decode(["uint256", "uint64", "bytes32"], data)
            jobs[jid] = dict(payee=addr(l["topics"][2]), token=addr(l["topics"][3]), amount=amount, dh=b"\x00" * 32)
            pending = (jid, 1, jobs[jid]["payee"], jobs[jid]["token"], amount, task)
        elif t0 == T_DELIV:
            jid = int(l["topics"][1], 16)
            (dh,) = decode(["bytes32"], data)
            jobs[jid]["dh"] = dh
            j = jobs[jid]
            pending = (jid, 2, j["payee"], j["token"], j["amount"], dh)
        elif t0 == T_DISPUTED:
            jid = int(l["topics"][1], 16)
            j = jobs[jid]
            pending = (jid, 3, j["payee"], j["token"], j["amount"], j["dh"])
        elif t0 == T_SETTLED:
            jid = int(l["topics"][1], 16)
            status, to_payee, _ref = decode(["uint8", "uint256", "uint256"], data)
            j = jobs[jid]
            pending = (jid, status, j["payee"], j["token"], to_payee, j["dh"])
        elif t0 == T_RECEIPT:
            jid, st, payee, token, amt, hh = pending
            enc = encode(["bytes32", "uint256", "uint8", "address", "address", "uint256", "bytes32"],
                         [head, jid, st, payee, token, amt, hh])
            head = keccak(enc)
            onchain = h(l["topics"][2])
            if head != onchain:
                print(f"FAIL receipt #{n} job {jid}: recomputed 0x{head.hex()} != on-chain 0x{onchain.hex()}")
                return False
            n += 1
    final = rpc(url, "eth_call", [{"to": wallet, "data": "0x" + keccak(b"logHead()")[:4].hex()}, "latest"])
    ok = h(final) == head
    print(f"{'OK' if ok else 'FAIL'}: {n} receipts re-derived, head 0x{head.hex()} {'==' if ok else '!='} on-chain {final}")
    return ok


if __name__ == "__main__":
    sys.exit(0 if verify(sys.argv[1], sys.argv[2], int(sys.argv[3]) if len(sys.argv) > 3 else 0) else 1)
