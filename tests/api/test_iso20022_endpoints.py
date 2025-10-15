import os
import uuid
import requests
import xml.etree.ElementTree as ET

BASE_URL = os.getenv("BASE_URL", "http://localhost:3000")

def _create_payment(amount_minor=12345, currency="EUR"):
    payload = {
        "externalId": str(uuid.uuid4()),
        "debtorIban": "SE12ABCDE1234567890123",
        "creditorIban": "SE34ABCDE9876543210123",
        "currency": currency,
        "amountMinor": amount_minor
    }
    idem = str(uuid.uuid4())
    r = requests.post(f"{BASE_URL}/payments", json=payload, headers={"Idempotency-Key": idem}, timeout=10)
    r.raise_for_status()
    return r.json()

def _find(root, tag):
    return root.find(f".//{{*}}{tag}")

def _findtext(root, tag):
    el = _find(root, tag)
    return el.text if el is not None else None

def test_pain001_xml_fields():
    payment = _create_payment()
    r = requests.get(f"{BASE_URL}/payments/{payment['id']}/pain001", timeout=10)
    assert r.status_code == 200
    root = ET.fromstring(r.text)
    assert _findtext(root, "MsgId") == payment["id"]
    assert _findtext(root, "EndToEndId") == payment["endToEndId"]
    assert _findtext(root, "IBAN") is not None
    assert _find(root, "InstdAmt").attrib.get("Ccy") == payment["currency"]

def test_pain002_xml_fields():
    payment = _create_payment()
    r = requests.get(f"{BASE_URL}/payments/{payment['id']}/pain002", timeout=10)
    assert r.status_code == 200
    root = ET.fromstring(r.text)
    assert _findtext(root, "OrgnlMsgId") == payment["id"]
    assert _findtext(root, "OrgnlEndToEndId") == payment["endToEndId"]
    assert _findtext(root, "TxSts") in ("ACSP", "RJCT")

def test_pacs008_xml_fields():
    payment = _create_payment()
    r = requests.get(f"{BASE_URL}/payments/{payment['id']}/pacs008", timeout=10)
    assert r.status_code == 200
    root = ET.fromstring(r.text)
    assert _findtext(root, "EndToEndId") == payment["endToEndId"]
    instd_amt = _find(root, "InstdAmt")
    assert instd_amt is not None and instd_amt.attrib.get("Ccy") == payment["currency"]

def test_pacs002_xml_fields():
    payment = _create_payment()
    r = requests.get(f"{BASE_URL}/payments/{payment['id']}/pacs002", timeout=10)
    assert r.status_code == 200
    root = ET.fromstring(r.text)
    assert _findtext(root, "OrgnlEndToEndId") == payment["endToEndId"]
    assert _findtext(root, "TxSts") in ("ACSP", "RJCT")

def test_camt054_xml_fields():
    payment = _create_payment()
    r = requests.get(f"{BASE_URL}/payments/{payment['id']}/camt054", timeout=10)
    assert r.status_code == 200
    root = ET.fromstring(r.text)
    assert _findtext(root, "NtryRef") == payment["id"]
    amt = _find(root, "Amt")
    assert amt is not None and amt.attrib.get("Ccy") == payment["currency"]

def test_camt053_xml_fields():
    # Create two to ensure multiple entries
    _ = _create_payment(10000, "EUR")
    _ = _create_payment(2500, "SEK")
    r = requests.get(f"{BASE_URL}/statements/camt053", timeout=10)
    assert r.status_code == 200
    root = ET.fromstring(r.text)
    nb_msgs = _findtext(root, "NbOfMsgs")
    assert nb_msgs is not None and int(nb_msgs) >= 2
    assert _find(root, "Ntry") is not None
