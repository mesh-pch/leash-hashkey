import json, hashlib, hmac
import hsp_topup as h

def test_signature_matches_spec():
    body = h.canonical_json({"b": 1, "a": [2, 1]})
    assert body == '{"a":[2,1],"b":1}'
    sig = h.sign("POST", "/api/v1/merchant/orders", "", body, "s3cret", 1700000000000, "n1")
    msg = "POST\n/api/v1/merchant/orders\n\n" + hashlib.sha256(body.encode()).hexdigest() + "\n1700000000000\nn1"
    assert sig == hmac.new(b"s3cret", msg.encode(), hashlib.sha256).hexdigest()

def test_order_targets_wallet():
    o = h.topup_order("0x" + "ab" * 20, "25.00", order_no="X1")
    d = o["cart_mandate"]["contents"]["payment_request"]["method_data"][0]["data"]
    assert d["pay_to"] == "0x" + "ab" * 20 and d["chain_id"] == 177
    assert o["amount"] == "25.00"

def test_headers_have_all_fields():
    hd = h.headers("GET", "/x", "a=1", "", "k", "s", 1, "n")
    assert set(hd) >= {"X-App-Key", "X-Timestamp", "X-Nonce", "X-Signature"}
