"""HSP (HashKey Settlement Platform) top-up adapter for a LeashWallet — human treasury -> agent wallet on-ramp.

Implements the HMAC-SHA256 request signing described in the HashKey Merchant API v2.3 docs as documented by community
integrations (message = METHOD\\nPATH\\nQUERY\\nsha256(canonical_body)\\nTIMESTAMP_MS\\nNONCE). It has NOT been run against
the live HSP gateway (merchant credentials are issued by HashKey); unit tests cover signing + request shaping only.
Credentials come from env: HSP_BASE_URL, HSP_APP_KEY, HSP_APP_SECRET. Nothing is hard-coded.
"""
import hashlib, hmac, json, os, time, uuid, urllib.request


def canonical_json(obj) -> str:
    # RFC 8785-style for our simple payloads: sorted keys, no whitespace, UTF-8
    return json.dumps(obj, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def sign(method: str, path: str, query: str, body: str, secret: str, ts_ms: int, nonce: str) -> str:
    body_hash = hashlib.sha256(body.encode()).hexdigest()
    msg = f"{method}\n{path}\n{query}\n{body_hash}\n{ts_ms}\n{nonce}"
    return hmac.new(secret.encode(), msg.encode(), hashlib.sha256).hexdigest()


def headers(method, path, query, body, app_key, secret, ts_ms=None, nonce=None):
    ts_ms = ts_ms or int(time.time() * 1000)
    nonce = nonce or uuid.uuid4().hex
    return {
        "Content-Type": "application/json",
        "X-App-Key": app_key,
        "X-Timestamp": str(ts_ms),
        "X-Nonce": nonce,
        "X-Signature": sign(method, path, query, body, secret, ts_ms, nonce),
    }


def topup_order(wallet: str, amount: str, token: str = "USDC", chain_id: int = 177, order_no: str | None = None) -> dict:
    """Cart for funding `wallet` (a LeashWallet) with `amount` of `token` on HashKey Chain."""
    order_no = order_no or f"LEASH_{int(time.time())}_{uuid.uuid4().hex[:6]}"
    return {
        "merchant_order_no": order_no,
        "cart_mandate": {"contents": {
            "id": f"mandate_{order_no}",
            "user_cart_confirmation_required": True,
            "payment_request": {
                "method_data": [{"supported_methods": "https://www.x402.org/",
                                 "data": {"x402Version": 2, "chain_id": chain_id, "pay_to": wallet, "coin": token}}],
                "details": {"id": f"details_{order_no}",
                            "display_items": [{"label": "Fund Leash agent wallet", "amount": {"currency": token, "value": amount}}],
                            "total": {"label": "Total", "amount": {"currency": token, "value": amount}}},
            }}},
        "amount": amount, "currency": token,
    }


def create_order(order: dict, base_url=None, app_key=None, secret=None):
    base_url = base_url or os.environ["HSP_BASE_URL"]
    app_key = app_key or os.environ["HSP_APP_KEY"]
    secret = secret or os.environ["HSP_APP_SECRET"]
    path, body = "/api/v1/merchant/orders", canonical_json(order)
    req = urllib.request.Request(base_url + path, body.encode(), headers("POST", path, "", body, app_key, secret), method="POST")
    return json.load(urllib.request.urlopen(req, timeout=20))
