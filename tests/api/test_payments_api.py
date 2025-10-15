import os
import uuid
import requests

BASE_URL = os.getenv("BASE_URL", "http://localhost:3000")

def test_health():
    r = requests.get(f"{BASE_URL}/health", timeout=5)
    assert r.status_code == 200
    assert r.json().get("status") == "ok"

def valid_payload():
    return {
        "externalId": str(uuid.uuid4()),
        "debtorIban": "SE12ABCDE1234567890123",
        "creditorIban": "SE34ABCDE9876543210123",
        "currency": "EUR",
        "amountMinor": 1000
    }

def test_create_payment_success():
    idem = str(uuid.uuid4())
    r = requests.post(f"{BASE_URL}/payments", json=valid_payload(), headers={"Idempotency-Key": idem}, timeout=10)
    assert r.status_code == 201
    body = r.json()
    assert body["status"] in ("INITIATED", "PENDING")
    assert body["currency"] in ("EUR", "SEK", "USD")
    assert isinstance(body["scheduledNextBusinessDay"], bool)

def test_validation_errors():
    idem = str(uuid.uuid4())
    bad = valid_payload()
    bad["currency"] = "XXX"
    bad["creditorIban"] = "BAD"
    r = requests.post(f"{BASE_URL}/payments", json=bad, headers={"Idempotency-Key": idem}, timeout=10)
    assert r.status_code == 400
    j = r.json()
    assert j["error"] == "validation"
    assert "currency invalid" in j["details"]
    assert "creditorIban invalid" in j["details"]

def test_idempotency_same_key_returns_same_resource():
    idem = str(uuid.uuid4())
    payload = valid_payload()
    r1 = requests.post(f"{BASE_URL}/payments", json=payload, headers={"Idempotency-Key": idem}, timeout=10)
    r2 = requests.post(f"{BASE_URL}/payments", json=payload, headers={"Idempotency-Key": idem}, timeout=10)
    assert r1.status_code == 201 and r2.status_code == 201
    assert r1.json()["id"] == r2.json()["id"]

def test_get_status():
    idem = str(uuid.uuid4())
    r = requests.post(f"{BASE_URL}/payments", json=valid_payload(), headers={"Idempotency-Key": idem}, timeout=10)
    pid = r.json()["id"]
    g = requests.get(f"{BASE_URL}/payments/{pid}", timeout=10)
    assert g.status_code == 200
    assert g.json()["id"] == pid

def test_cutoff_logic_flag_present():
    idem = str(uuid.uuid4())
    r = requests.post(f"{BASE_URL}/payments", json=valid_payload(), headers={"Idempotency-Key": idem}, timeout=10)
    assert r.status_code == 201
    assert isinstance(r.json()["scheduledNextBusinessDay"], bool)
