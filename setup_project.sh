#!/bin/sh
set -eu

# Make sure main is up to date
git fetch origin
git checkout main || git checkout -b main
git pull --rebase origin main

# Create and switch to new branch
git checkout -b setup-mock-api-and-ci || git switch setup-mock-api-and-ci

# Folders
mkdir -p api mocks/server tests/api tests/performance sql .github/workflows

# requirements.txt
cat > requirements.txt << 'TXT'
pytest==8.3.3
requests==2.32.3
TXT

# .gitignore
cat > .gitignore << 'TXT'
# Node
mocks/server/node_modules
npm-debug.log*

# Python
__pycache__/
*.pyc

# OS
.DS_Store
TXT

# api/openapi.yaml
cat > api/openapi.yaml << 'YAML'
openapi: 3.0.3
info:
  title: Credit Transfer API (Mock)
  version: "1.2.0"
servers:
  - url: http://localhost:3000
paths:
  /health:
    get:
      summary: Healthcheck
      responses:
        '200':
          description: OK
  /payments:
    post:
      summary: Create a payment
      parameters:
        - in: header
          name: Idempotency-Key
          required: true
          schema: { type: string }
      requestBody:
        required: true
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/CreatePaymentRequest'
      responses:
        '201':
          description: Created
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/Payment'
        '400':
          description: Validation error
  /payments/{id}:
    get:
      summary: Get payment by id
      parameters:
        - in: path
          name: id
          required: true
          schema: { type: string }
      responses:
        '200':
          description: Payment
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/Payment'
        '404':
          description: Not Found
  /payments/{id}/pain001:
    get:
      summary: Export payment as pain.001 XML (simplified)
      parameters:
        - in: path
          name: id
          required: true
          schema: { type: string }
      responses:
        '200':
          description: pain.001 XML
          content:
            application/xml:
              schema: { type: string }
        '404':
          description: Not Found
  /payments/{id}/pain002:
    get:
      summary: Export payment as pain.002 XML (simplified)
      parameters:
        - in: path
          name: id
          required: true
          schema: { type: string }
      responses:
        '200':
          description: pain.002 XML
          content:
            application/xml:
              schema: { type: string }
        '404':
          description: Not Found
  /payments/{id}/pacs008:
    get:
      summary: Export payment as pacs.008 XML (simplified)
      parameters:
        - in: path
          name: id
          required: true
          schema: { type: string }
      responses:
        '200':
          description: pacs.008 XML
          content:
            application/xml:
              schema: { type: string }
        '404':
          description: Not Found
  /payments/{id}/pacs002:
    get:
      summary: Export payment status as pacs.002 XML (simplified)
      parameters:
        - in: path
          name: id
          required: true
          schema: { type: string }
      responses:
        '200':
          description: pacs.002 XML
          content:
            application/xml:
              schema: { type: string }
        '404':
          description: Not Found
  /payments/{id}/camt054:
    get:
      summary: Export single payment notification as camt.054 XML (simplified)
      parameters:
        - in: path
          name: id
          required: true
          schema: { type: string }
      responses:
        '200':
          description: camt.054 XML
          content:
            application/xml:
              schema: { type: string }
        '404':
          description: Not Found
  /statements/camt053:
    get:
      summary: Export statement as camt.053 XML (simplified)
      responses:
        '200':
          description: camt.053 XML
          content:
            application/xml:
              schema: { type: string }
components:
  schemas:
    CreatePaymentRequest:
      type: object
      required: [externalId, debtorIban, creditorIban, currency, amountMinor]
      properties:
        externalId: { type: string }
        debtorIban: { type: string, description: "IBAN-like format" }
        creditorIban: { type: string, description: "IBAN-like format" }
        currency:
          type: string
          enum: [EUR, SEK, USD]
        amountMinor:
          type: integer
          minimum: 1
        endToEndId: { type: string }
        requestedExecutionDate:
          type: string
          format: date
    Payment:
      type: object
      properties:
        id: { type: string }
        externalId: { type: string }
        debtorIban: { type: string }
        creditorIban: { type: string }
        currency: { type: string }
        amountMinor: { type: integer }
        status:
          type: string
          enum: [INITIATED, PENDING, AUTHORIZED, SETTLED, REJECTED]
        scheduledNextBusinessDay: { type: boolean }
        endToEndId: { type: string }
        requestedExecutionDate: { type: string, format: date }
        createdAt: { type: string, format: date-time }
YAML

# mocks/server/package.json
mkdir -p mocks/server
cat > mocks/server/package.json << 'JSON'
{
  "name": "payments-mock-api",
  "version": "1.0.0",
  "private": true,
  "type": "module",
  "scripts": {
    "start": "node server.js",
    "dev": "node --watch server.js"
  },
  "dependencies": {
    "cors": "^2.8.5",
    "dayjs": "^1.11.13",
    "express": "^4.19.2",
    "uuid": "^11.0.3"
  }
}
JSON

# mocks/server/server.js
cat > mocks/server/server.js << 'JS'
import express from 'express';
import cors from 'cors';
import { v4 as uuidv4 } from 'uuid';
import dayjs from 'dayjs';

const app = express();
app.use(cors());
app.use(express.json());

// In-memory stores
const payments = new Map();
const idemKeys = new Map();

// Validators
const isIbanLike = (s) => typeof s === 'string' && /^[A-Z]{2}\d{2}[A-Z0-9]{10,30}$/.test(s);
const isCurrency = (s) => ['EUR', 'SEK', 'USD'].includes(s);
const isPositiveInt = (n) => Number.isInteger(n) && n > 0;

// Cut-off utility: after 16:00 local => schedule next business day
function isAfterCutoff() {
  const now = dayjs();
  const cutoff = now.hour(16).minute(0).second(0);
  return now.isAfter(cutoff);
}

function majorAmount(p) {
  return (p.amountMinor / 100).toFixed(2);
}

function xmlHeader(ns) {
  return `<?xml version="1.0" encoding="UTF-8"?>\n<Document xmlns="${ns}">`;
}

// Health
app.get('/health', (_req, res) => res.status(200).json({ status: 'ok' }));

// Create payment
app.post('/payments', (req, res) => {
  const idem = req.header('Idempotency-Key');
  if (!idem) return res.status(400).json({ error: 'Missing Idempotency-Key header' });

  if (idemKeys.has(idem)) {
    const existingId = idemKeys.get(idem);
    const existing = payments.get(existingId);
    return res.status(201).json(existing);
  }

  const { externalId, debtorIban, creditorIban, currency, amountMinor, endToEndId, requestedExecutionDate } = req.body || {};
  const errors = [];
  if (!externalId) errors.push('externalId required');
  if (!isIbanLike(debtorIban)) errors.push('debtorIban invalid');
  if (!isIbanLike(creditorIban)) errors.push('creditorIban invalid');
  if (!isCurrency(currency)) errors.push('currency invalid');
  if (!isPositiveInt(amountMinor)) errors.push('amountMinor invalid');
  if (errors.length) return res.status(400).json({ error: 'validation', details: errors });

  const id = uuidv4();
  const now = dayjs().toISOString();
  const scheduledNextBusinessDay = isAfterCutoff();

  const payment = {
    id,
    externalId,
    debtorIban,
    creditorIban,
    currency,
    amountMinor,
    endToEndId: endToEndId || uuidv4(),
    requestedExecutionDate: requestedExecutionDate || dayjs().format('YYYY-MM-DD'),
    status: 'INITIATED',
    scheduledNextBusinessDay,
    createdAt: now
  };

  payments.set(id, payment);
  idemKeys.set(idem, id);

  // Simulate async move to PENDING
  setTimeout(() => {
    const p = payments.get(id);
    if (p && p.status === 'INITIATED') {
      p.status = 'PENDING';
      payments.set(id, p);
    }
  }, 50);

  return res.status(201).json(payment);
});

// Get payment
app.get('/payments/:id', (req, res) => {
  const p = payments.get(req.params.id);
  if (!p) return res.status(404).json({ error: 'not_found' });
  res.json(p);
});

// pain.001
app.get('/payments/:id/pain001', (req, res) => {
  const p = payments.get(req.params.id);
  if (!p) return res.status(404).send('Not Found');
  const amt = majorAmount(p);
  const ns = 'urn:iso:std:iso:20022:tech:xsd:pain.001.001.03';
  const xml = `${xmlHeader(ns)}
  <CstmrCdtTrfInitn>
    <GrpHdr>
      <MsgId>${p.id}</MsgId>
      <CreDtTm>${p.createdAt}</CreDtTm>
      <NbOfTxs>1</NbOfTxs>
      <CtrlSum>${amt}</CtrlSum>
    </GrpHdr>
    <PmtInf>
      <PmtInfId>${p.externalId}</PmtInfId>
      <BtchBookg>false</BtchBookg>
      <NbOfTxs>1</NbOfTxs>
      <CtrlSum>${amt}</CtrlSum>
      <ReqdExctnDt>${p.requestedExecutionDate}</ReqdExctnDt>
      <Dbtr><Nm>Debtor</Nm></Dbtr>
      <DbtrAcct><Id><IBAN>${p.debtorIban}</IBAN></Id></DbtrAcct>
      <CdtTrfTxInf>
        <PmtId><EndToEndId>${p.endToEndId}</EndToEndId></PmtId>
        <Amt><InstdAmt Ccy="${p.currency}">${amt}</InstdAmt></Amt>
        <Cdtr><Nm>Creditor</Nm></Cdtr>
        <CdtrAcct><Id><IBAN>${p.creditorIban}</IBAN></Id></CdtrAcct>
      </CdtTrfTxInf>
    </PmtInf>
  </CstmrCdtTrfInitn>
</Document>`;
  res.set('Content-Type', 'application/xml').status(200).send(xml);
}

// pain.002
app.get('/payments/:id/pain002', (req, res) => {
  const p = payments.get(req.params.id);
  if (!p) return res.status(404).send('Not Found');
  const ns = 'urn:iso:std:iso:20022:tech:xsd:pain.002.001.03';
  const status = p.status === 'REJECTED' ? 'RJCT' : 'ACSP';
  const xml = `${xmlHeader(ns)}
  <CstmrPmtStsRpt>
    <GrpHdr>
      <MsgId>${p.id}-status</MsgId>
      <CreDtTm>${dayjs().toISOString()}</CreDtTm>
    </GrpHdr>
    <OrgnlGrpInfAndSts>
      <OrgnlMsgId>${p.id}</OrgnlMsgId>
      <OrgnlMsgNmId>pain.001.001.03</OrgnlMsgNmId>
    </OrgnlGrpInfAndSts>
    <OrgnlPmtInfAndSts>
      <TxInfAndSts>
        <OrgnlEndToEndId>${p.endToEndId}</OrgnlEndToEndId>
        <TxSts>${status}</TxSts>
      </TxInfAndSts>
    </OrgnlPmtInfAndSts>
  </CstmrPmtStsRpt>
</Document>`;
  res.set('Content-Type', 'application/xml').status(200).send(xml);
});

// pacs.008
app.get('/payments/:id/pacs008', (req, res) => {
  const p = payments.get(req.params.id);
  if (!p) return res.status(404).send('Not Found');
  const amt = majorAmount(p);
  const ns = 'urn:iso:std:iso:20022:tech:xsd:pacs.008.001.02';
  const xml = `${xmlHeader(ns)}
  <FIToFICstmrCdtTrf>
    <GrpHdr>
      <MsgId>${p.id}-pacs008</MsgId>
      <CreDtTm>${p.createdAt}</CreDtTm>
      <NbOfTxs>1</NbOfTxs>
      <CtrlSum>${amt}</CtrlSum>
    </GrpHdr>
    <CdtTrfTxInf>
      <PmtId><EndToEndId>${p.endToEndId}</EndToEndId></PmtId>
      <Amt><InstdAmt Ccy="${p.currency}">${amt}</InstdAmt></Amt>
      <DbtrAcct><Id><IBAN>${p.debtorIban}</IBAN></Id></DbtrAcct>
      <CdtrAcct><Id><IBAN>${p.creditorIban}</IBAN></Id></CdtrAcct>
    </CdtTrfTxInf>
  </FIToFICstmrCdtTrf>
</Document>`;
  res.set('Content-Type', 'application/xml').status(200).send(xml);
});

// pacs.002
app.get('/payments/:id/pacs002', (req, res) => {
  const p = payments.get(req.params.id);
  if (!p) return res.status(404).send('Not Found');
  const ns = 'urn:iso:std:iso:20022:tech:xsd:pacs.002.001.03';
  const status = p.status === 'REJECTED' ? 'RJCT' : 'ACSP';
  const xml = `${xmlHeader(ns)}
  <FIToFIPmtStsRpt>
    <GrpHdr>
      <MsgId>${p.id}-pacs002</MsgId>
      <CreDtTm>${dayjs().toISOString()}</CreDtTm>
    </GrpHdr>
    <OrgnlGrpInfAndSts>
      <OrgnlMsgId>${p.id}-pacs008</OrgnlMsgId>
      <OrgnlMsgNmId>pacs.008.001.02</OrgnlMsgNmId>
    </OrgnlGrpInfAndSts>
    <TxInfAndSts>
      <OrgnlEndToEndId>${p.endToEndId}</OrgnlEndToEndId>
      <TxSts>${status}</TxSts>
    </TxInfAndSts>
  </FIToFIPmtStsRpt>
</Document>`;
  res.set('Content-Type', 'application/xml').status(200).send(xml);
});

// camt.054
app.get('/payments/:id/camt054', (req, res) => {
  const p = payments.get(req.params.id);
  if (!p) return res.status(404).send('Not Found');
  const amt = majorAmount(p);
  const ns = 'urn:iso:std:iso:20022:tech:xsd:camt.054.001.04';
  const xml = `${xmlHeader(ns)}
  <BkToCstmrDbtCdtNtfctn>
    <GrpHdr>
      <MsgId>${p.id}-camt054</MsgId>
      <CreDtTm>${dayjs().toISOString()}</CreDtTm>
    </GrpHdr>
    <Ntfctn>
      <Id>${p.id}</Id>
      <NtfctnPgntn><PgNb>1</PgNb><LastPgInd>true</LastPgInd></NtfctnPgntn>
      <Ntry>
        <NtryRef>${p.id}</NtryRef>
        <Amt Ccy="${p.currency}">${amt}</Amt>
        <CdtDbtInd>CRDT</CdtDbtInd>
        <BkTxCd><Prtry>TRF</Prtry></BkTxCd>
        <NtryDtls>
          <TxDtls>
            <Refs><EndToEndId>${p.endToEndId}</EndToEndId></Refs>
            <RmtInf><Ustrd>${p.endToEndId}</Ustrd></RmtInf>
          </TxDtls>
        </NtryDtls>
      </Ntry>
    </Ntfctn>
  </BkToCstmrDbtCdtNtfctn>
</Document>`;
  res.set('Content-Type', 'application/xml').status(200).send(xml);
});

// camt.053
app.get('/statements/camt053', (_req, res) => {
  const ns = 'urn:iso:std:iso:20022:tech:xsd:camt.053.001.02';
  const all = Array.from(payments.values());
  const count = all.length;
  const sum = all.reduce((acc, p) => acc + p.amountMinor, 0) / 100;
  const xmlEntries = all.map((p) => {
    return `<Ntry>
      <Amt Ccy="${p.currency}">${(p.amountMinor/100).toFixed(2)}</Amt>
      <CdtDbtInd>CRDT</CdtDbtInd>
      <NtryRef>${p.id}</NtryRef>
      <NtryDtls>
        <TxDtls>
          <Refs><EndToEndId>${p.endToEndId}</EndToEndId></Refs>
        </TxDtls>
      </NtryDtls>
    </Ntry>`;
  }).join('\n');

  const xml = `${xmlHeader(ns)}
  <BkToCstmrStmt>
    <GrpHdr>
      <MsgId>statement-${dayjs().format('YYYYMMDDHHmmss')}</MsgId>
      <CreDtTm>${dayjs().toISOString()}</CreDtTm>
      <NbOfMsgs>${count}</NbOfMsgs>
      <CtrlSum>${(sum).toFixed(2)}</CtrlSum>
    </GrpHdr>
    <Stmt>
      <Id>${uuidv4()}</Id>
      ${xmlEntries}
    </Stmt>
  </BkToCstmrStmt>
</Document>`;
  res.set('Content-Type', 'application/xml').status(200).send(xml);
});

// Test-only reset
app.post('/__reset', (_req, res) => {
  payments.clear();
  idemKeys.clear();
  res.status(204).end();
});

const port = process.env.PORT || 3000;
app.listen(port, () => {
  console.log(`Mock API on http://localhost:${port}`);
});
JS

# tests/api
mkdir -p tests/api
cat > tests/api/conftest.py << 'PY'
import os
import requests
import pytest

BASE_URL = os.getenv("BASE_URL", "http://localhost:3000")

@pytest.fixture(autouse=True)
def reset_env():
    try:
        requests.post(f"{BASE_URL}/__reset", timeout=5)
    except Exception:
        pass
    yield
PY

cat > tests/api/test_payments_api.py << 'PY'
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
PY

# tests/api/test_iso20022_endpoints.py
cat > tests/api/test_iso20022_endpoints.py << 'PY'
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
PY

# tests/performance/create_payment.js
mkdir -p tests/performance
cat > tests/performance/create_payment.js << 'JS'
import http from 'k6/http';
import { check, sleep } from 'k6';

export const options = {
  vus: 5,
  duration: '10s',
  thresholds: {
    http_req_duration: ['p(95)<300'],
    http_req_failed: ['rate<0.01']
  }
};

const BASE_URL = __ENV.BASE_URL || 'http://localhost:3000';

export default function () {
  const payload = JSON.stringify({
    externalId: `${__VU}-${__ITER}-${Date.now()}`,
    debtorIban: 'SE12ABCDE1234567890123',
    creditorIban: 'SE34ABCDE9876543210123',
    currency: 'EUR',
    amountMinor: 1000
  });
  const headers = {
    'Content-Type': 'application/json',
    'Idempotency-Key': `${__VU}-${__ITER}`
  };
  const res = http.post(`${BASE_URL}/payments`, payload, { headers });
  check(res, {
    'status 201': (r) => r.status === 201,
    'has id': (r) => !!r.json('id'),
  });
  sleep(0.2);
}
JS

# SQL
mkdir -p sql
cat > sql/schema.sql << 'SQL'
CREATE TABLE IF NOT EXISTS payments (
  id TEXT PRIMARY KEY,
  external_id TEXT NOT NULL,
  debtor_iban TEXT NOT NULL,
  creditor_iban TEXT NOT NULL,
  currency TEXT NOT NULL,
  amount_minor INTEGER NOT NULL,
  status TEXT NOT NULL,
  created_at TIMESTAMP NOT NULL
);

CREATE TABLE IF NOT EXISTS ledger_entries (
  id TEXT PRIMARY KEY,
  payment_id TEXT NOT NULL,
  direction TEXT NOT NULL,
  amount_minor INTEGER NOT NULL,
  currency TEXT NOT NULL,
  posted_at TIMESTAMP NOT NULL
);

CREATE TABLE IF NOT EXISTS webhooks (
  id TEXT PRIMARY KEY,
  payment_id TEXT NOT NULL,
  event TEXT NOT NULL,
  delivered_at TIMESTAMP NOT NULL,
  retry_count INTEGER NOT NULL DEFAULT 0
);
SQL

cat > sql/seed.sql << 'SQL'
INSERT INTO payments (id, external_id, debtor_iban, creditor_iban, currency, amount_minor, status, created_at)
VALUES
('p1','ext-1','SE12ABCDE1234567890123','SE34ABCDE9876543210123','EUR',1000,'SETTLED', NOW()),
('p2','ext-2','SE12ABCDE1234567890123','SE34ABCDE9876543210123','EUR',2000,'SETTLED', NOW()),
('p3','ext-3','SE12ABCDE1234567890123','SE34ABCDE9876543210123','EUR',1000,'PENDING', NOW());

INSERT INTO ledger_entries (id, payment_id, direction, amount_minor, currency, posted_at)
VALUES
('l1','p1','SETTLE',1000,'EUR', NOW()),
('l2','pX','SETTLE',500,'EUR', NOW());
SQL

cat > sql/recon_queries.sql << 'SQL'
-- Settled payments missing ledger postings
SELECT p.id, p.external_id
FROM payments p
LEFT JOIN ledger_entries l
ON l.payment_id = p.id AND l.direction = 'SETTLE'
WHERE p.status = 'SETTLED' AND l.id IS NULL;

-- Potential duplicates (same debtor/creditor/amount within 5 min)
SELECT a.id AS p1, b.id AS p2, a.debtor_iban, a.creditor_iban, a.amount_minor, a.currency
FROM payments a
JOIN payments b
  ON a.debtor_iban = b.debtor_iban
 AND a.creditor_iban = b.creditor_iban
 AND a.amount_minor = b.amount_minor
 AND a.currency = b.currency
 AND a.id <> b.id
 AND ABS(EXTRACT(EPOCH FROM (a.created_at - b.created_at))) <= 300;

-- Reconcile sums between payments and ledger by currency
SELECT p.currency,
       SUM(CASE WHEN p.status='SETTLED' THEN p.amount_minor ELSE 0 END) AS settled_amount,
       SUM(CASE WHEN l.direction='SETTLE' THEN l.amount_minor ELSE 0 END) AS ledger_amount
FROM payments p
LEFT JOIN ledger_entries l ON l.payment_id = p.id
GROUP BY p.currency
HAVING SUM(CASE WHEN p.status='SETTLED' THEN p.amount_minor END)
    <> SUM(CASE WHEN l.direction='SETTLE' THEN l.amount_minor END);

-- Orphaned webhooks
SELECT w.*
FROM webhooks w
LEFT JOIN payments p ON p.id = w.payment_id
WHERE p.id IS NULL;

-- Payments stuck in PENDING > 2 hours
SELECT *
FROM payments
WHERE status='PENDING' AND created_at < NOW() - INTERVAL '2 hours';
SQL

# CI
mkdir -p .github/workflows
cat > .github/workflows/ci.yml << 'YML'
name: CI

on:
  push:
  pull_request:

jobs:
  test:
    runs-on: ubuntu-latest
    env:
      BASE_URL: http://localhost:3000
    steps:
      - uses: actions/checkout@v4

      - name: Set up Node
        uses: actions/setup-node@v4
        with:
          node-version: '18'

      - name: Install and start mock API
        working-directory: mocks/server
        run: |
          npm ci
          nohup npm start &
          sleep 2
          curl -fsS http://localhost:3000/health

      - name: Set up Python
        uses: actions/setup-python@v5
        with:
          python-version: '3.10'

      - name: Install Python deps
        run: pip install -r requirements.txt

      - name: Run API tests
        run: pytest -q

      - name: Install k6
        run: |
          sudo apt-get update
          sudo apt-get install -y gnupg software-properties-common
          curl -fsSL https://dl.k6.io/key.gpg | sudo gpg --dearmor -o /usr/share/keyrings/k6-archive-keyring.gpg
          echo "deb [signed-by=/usr/share/keyrings/k6-archive-keyring.gpg] https://dl.k6.io/deb stable main" | sudo tee /etc/apt/sources.list.d/k6.list
          sudo apt-get update
          sudo apt-get install -y k6

      - name: Performance smoke
        run: k6 run tests/performance/create_payment.js
YML

# Stage, commit, push
git add api/openapi.yaml mocks/server/package.json mocks/server/server.js \
        requirements.txt tests/api/conftest.py tests/api/test_payments_api.py tests/api/test_iso20022_endpoints.py \
        tests/performance/create_payment.js sql/schema.sql sql/seed.sql sql/recon_queries.sql \
        .github/workflows/ci.yml .gitignore

git commit -m "Add mock API, tests, OpenAPI, SQL, and CI (no README changes)"
git push -u origin setup-mock-api-and-ci

echo
echo "Open PR:"
echo "https://github.com/mmljay/corporate-payments-ba-qa-portfolio/compare/main...setup-mock-api-and-ci"
EOFcat > setup_project.sh << 'EOF'
#!/bin/sh
set -eu

# Make sure main is up to date
git fetch origin
git checkout main || git checkout -b main
git pull --rebase origin main

# Create and switch to new branch
git checkout -b setup-mock-api-and-ci || git switch setup-mock-api-and-ci

# Folders
mkdir -p api mocks/server tests/api tests/performance sql .github/workflows

# requirements.txt
cat > requirements.txt << 'TXT'
pytest==8.3.3
requests==2.32.3
TXT

# .gitignore
cat > .gitignore << 'TXT'
# Node
mocks/server/node_modules
npm-debug.log*

# Python
__pycache__/
*.pyc

# OS
.DS_Store
TXT

# api/openapi.yaml
cat > api/openapi.yaml << 'YAML'
openapi: 3.0.3
info:
  title: Credit Transfer API (Mock)
  version: "1.2.0"
servers:
  - url: http://localhost:3000
paths:
  /health:
    get:
      summary: Healthcheck
      responses:
        '200':
          description: OK
  /payments:
    post:
      summary: Create a payment
      parameters:
        - in: header
          name: Idempotency-Key
          required: true
          schema: { type: string }
      requestBody:
        required: true
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/CreatePaymentRequest'
      responses:
        '201':
          description: Created
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/Payment'
        '400':
          description: Validation error
  /payments/{id}:
    get:
      summary: Get payment by id
      parameters:
        - in: path
          name: id
          required: true
          schema: { type: string }
      responses:
        '200':
          description: Payment
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/Payment'
        '404':
          description: Not Found
  /payments/{id}/pain001:
    get:
      summary: Export payment as pain.001 XML (simplified)
      parameters:
        - in: path
          name: id
          required: true
          schema: { type: string }
      responses:
        '200':
          description: pain.001 XML
          content:
            application/xml:
              schema: { type: string }
        '404':
          description: Not Found
  /payments/{id}/pain002:
    get:
      summary: Export payment as pain.002 XML (simplified)
      parameters:
        - in: path
          name: id
          required: true
          schema: { type: string }
      responses:
        '200':
          description: pain.002 XML
          content:
            application/xml:
              schema: { type: string }
        '404':
          description: Not Found
  /payments/{id}/pacs008:
    get:
      summary: Export payment as pacs.008 XML (simplified)
      parameters:
        - in: path
          name: id
          required: true
          schema: { type: string }
      responses:
        '200':
          description: pacs.008 XML
          content:
            application/xml:
              schema: { type: string }
        '404':
          description: Not Found
  /payments/{id}/pacs002:
    get:
      summary: Export payment status as pacs.002 XML (simplified)
      parameters:
        - in: path
          name: id
          required: true
          schema: { type: string }
      responses:
        '200':
          description: pacs.002 XML
          content:
            application/xml:
              schema: { type: string }
        '404':
          description: Not Found
  /payments/{id}/camt054:
    get:
      summary: Export single payment notification as camt.054 XML (simplified)
      parameters:
        - in: path
          name: id
          required: true
          schema: { type: string }
      responses:
        '200':
          description: camt.054 XML
          content:
            application/xml:
              schema: { type: string }
        '404':
          description: Not Found
  /statements/camt053:
    get:
      summary: Export statement as camt.053 XML (simplified)
      responses:
        '200':
          description: camt.053 XML
          content:
            application/xml:
              schema: { type: string }
components:
  schemas:
    CreatePaymentRequest:
      type: object
      required: [externalId, debtorIban, creditorIban, currency, amountMinor]
      properties:
        externalId: { type: string }
        debtorIban: { type: string, description: "IBAN-like format" }
        creditorIban: { type: string, description: "IBAN-like format" }
        currency:
          type: string
          enum: [EUR, SEK, USD]
        amountMinor:
          type: integer
          minimum: 1
        endToEndId: { type: string }
        requestedExecutionDate:
          type: string
          format: date
    Payment:
      type: object
      properties:
        id: { type: string }
        externalId: { type: string }
        debtorIban: { type: string }
        creditorIban: { type: string }
        currency: { type: string }
        amountMinor: { type: integer }
        status:
          type: string
          enum: [INITIATED, PENDING, AUTHORIZED, SETTLED, REJECTED]
        scheduledNextBusinessDay: { type: boolean }
        endToEndId: { type: string }
        requestedExecutionDate: { type: string, format: date }
        createdAt: { type: string, format: date-time }
YAML

# mocks/server/package.json
mkdir -p mocks/server
cat > mocks/server/package.json << 'JSON'
{
  "name": "payments-mock-api",
  "version": "1.0.0",
  "private": true,
  "type": "module",
  "scripts": {
    "start": "node server.js",
    "dev": "node --watch server.js"
  },
  "dependencies": {
    "cors": "^2.8.5",
    "dayjs": "^1.11.13",
    "express": "^4.19.2",
    "uuid": "^11.0.3"
  }
}
JSON

# mocks/server/server.js
cat > mocks/server/server.js << 'JS'
import express from 'express';
import cors from 'cors';
import { v4 as uuidv4 } from 'uuid';
import dayjs from 'dayjs';

const app = express();
app.use(cors());
app.use(express.json());

// In-memory stores
const payments = new Map();
const idemKeys = new Map();

// Validators
const isIbanLike = (s) => typeof s === 'string' && /^[A-Z]{2}\d{2}[A-Z0-9]{10,30}$/.test(s);
const isCurrency = (s) => ['EUR', 'SEK', 'USD'].includes(s);
const isPositiveInt = (n) => Number.isInteger(n) && n > 0;

// Cut-off utility: after 16:00 local => schedule next business day
function isAfterCutoff() {
  const now = dayjs();
  const cutoff = now.hour(16).minute(0).second(0);
  return now.isAfter(cutoff);
}

function majorAmount(p) {
  return (p.amountMinor / 100).toFixed(2);
}

function xmlHeader(ns) {
  return `<?xml version="1.0" encoding="UTF-8"?>\n<Document xmlns="${ns}">`;
}

// Health
app.get('/health', (_req, res) => res.status(200).json({ status: 'ok' }));

// Create payment
app.post('/payments', (req, res) => {
  const idem = req.header('Idempotency-Key');
  if (!idem) return res.status(400).json({ error: 'Missing Idempotency-Key header' });

  if (idemKeys.has(idem)) {
    const existingId = idemKeys.get(idem);
    const existing = payments.get(existingId);
    return res.status(201).json(existing);
  }

  const { externalId, debtorIban, creditorIban, currency, amountMinor, endToEndId, requestedExecutionDate } = req.body || {};
  const errors = [];
  if (!externalId) errors.push('externalId required');
  if (!isIbanLike(debtorIban)) errors.push('debtorIban invalid');
  if (!isIbanLike(creditorIban)) errors.push('creditorIban invalid');
  if (!isCurrency(currency)) errors.push('currency invalid');
  if (!isPositiveInt(amountMinor)) errors.push('amountMinor invalid');
  if (errors.length) return res.status(400).json({ error: 'validation', details: errors });

  const id = uuidv4();
  const now = dayjs().toISOString();
  const scheduledNextBusinessDay = isAfterCutoff();

  const payment = {
    id,
    externalId,
    debtorIban,
    creditorIban,
    currency,
    amountMinor,
    endToEndId: endToEndId || uuidv4(),
    requestedExecutionDate: requestedExecutionDate || dayjs().format('YYYY-MM-DD'),
    status: 'INITIATED',
    scheduledNextBusinessDay,
    createdAt: now
  };

  payments.set(id, payment);
  idemKeys.set(idem, id);

  // Simulate async move to PENDING
  setTimeout(() => {
    const p = payments.get(id);
    if (p && p.status === 'INITIATED') {
      p.status = 'PENDING';
      payments.set(id, p);
    }
  }, 50);

  return res.status(201).json(payment);
});

// Get payment
app.get('/payments/:id', (req, res) => {
  const p = payments.get(req.params.id);
  if (!p) return res.status(404).json({ error: 'not_found' });
  res.json(p);
});

// pain.001
app.get('/payments/:id/pain001', (req, res) => {
  const p = payments.get(req.params.id);
  if (!p) return res.status(404).send('Not Found');
  const amt = majorAmount(p);
  const ns = 'urn:iso:std:iso:20022:tech:xsd:pain.001.001.03';
  const xml = `${xmlHeader(ns)}
  <CstmrCdtTrfInitn>
    <GrpHdr>
      <MsgId>${p.id}</MsgId>
      <CreDtTm>${p.createdAt}</CreDtTm>
      <NbOfTxs>1</NbOfTxs>
      <CtrlSum>${amt}</CtrlSum>
    </GrpHdr>
    <PmtInf>
      <PmtInfId>${p.externalId}</PmtInfId>
      <BtchBookg>false</BtchBookg>
      <NbOfTxs>1</NbOfTxs>
      <CtrlSum>${amt}</CtrlSum>
      <ReqdExctnDt>${p.requestedExecutionDate}</ReqdExctnDt>
      <Dbtr><Nm>Debtor</Nm></Dbtr>
      <DbtrAcct><Id><IBAN>${p.debtorIban}</IBAN></Id></DbtrAcct>
      <CdtTrfTxInf>
        <PmtId><EndToEndId>${p.endToEndId}</EndToEndId></PmtId>
        <Amt><InstdAmt Ccy="${p.currency}">${amt}</InstdAmt></Amt>
        <Cdtr><Nm>Creditor</Nm></Cdtr>
        <CdtrAcct><Id><IBAN>${p.creditorIban}</IBAN></Id></CdtrAcct>
      </CdtTrfTxInf>
    </PmtInf>
  </CstmrCdtTrfInitn>
</Document>`;
  res.set('Content-Type', 'application/xml').status(200).send(xml);
}

// pain.002
app.get('/payments/:id/pain002', (req, res) => {
  const p = payments.get(req.params.id);
  if (!p) return res.status(404).send('Not Found');
  const ns = 'urn:iso:std:iso:20022:tech:xsd:pain.002.001.03';
  const status = p.status === 'REJECTED' ? 'RJCT' : 'ACSP';
  const xml = `${xmlHeader(ns)}
  <CstmrPmtStsRpt>
    <GrpHdr>
      <MsgId>${p.id}-status</MsgId>
      <CreDtTm>${dayjs().toISOString()}</CreDtTm>
    </GrpHdr>
    <OrgnlGrpInfAndSts>
      <OrgnlMsgId>${p.id}</OrgnlMsgId>
      <OrgnlMsgNmId>pain.001.001.03</OrgnlMsgNmId>
    </OrgnlGrpInfAndSts>
    <OrgnlPmtInfAndSts>
      <TxInfAndSts>
        <OrgnlEndToEndId>${p.endToEndId}</OrgnlEndToEndId>
        <TxSts>${status}</TxSts>
      </TxInfAndSts>
    </OrgnlPmtInfAndSts>
  </CstmrPmtStsRpt>
</Document>`;
  res.set('Content-Type', 'application/xml').status(200).send(xml);
});

// pacs.008
app.get('/payments/:id/pacs008', (req, res) => {
  const p = payments.get(req.params.id);
  if (!p) return res.status(404).send('Not Found');
  const amt = majorAmount(p);
  const ns = 'urn:iso:std:iso:20022:tech:xsd:pacs.008.001.02';
  const xml = `${xmlHeader(ns)}
  <FIToFICstmrCdtTrf>
    <GrpHdr>
      <MsgId>${p.id}-pacs008</MsgId>
      <CreDtTm>${p.createdAt}</CreDtTm>
      <NbOfTxs>1</NbOfTxs>
      <CtrlSum>${amt}</CtrlSum>
    </GrpHdr>
    <CdtTrfTxInf>
      <PmtId><EndToEndId>${p.endToEndId}</EndToEndId></PmtId>
      <Amt><InstdAmt Ccy="${p.currency}">${amt}</InstdAmt></Amt>
      <DbtrAcct><Id><IBAN>${p.debtorIban}</IBAN></Id></DbtrAcct>
      <CdtrAcct><Id><IBAN>${p.creditorIban}</IBAN></Id></CdtrAcct>
    </CdtTrfTxInf>
  </FIToFICstmrCdtTrf>
</Document>`;
  res.set('Content-Type', 'application/xml').status(200).send(xml);
});

// pacs.002
app.get('/payments/:id/pacs002', (req, res) => {
  const p = payments.get(req.params.id);
  if (!p) return res.status(404).send('Not Found');
  const ns = 'urn:iso:std:iso:20022:tech:xsd:pacs.002.001.03';
  const status = p.status === 'REJECTED' ? 'RJCT' : 'ACSP';
  const xml = `${xmlHeader(ns)}
  <FIToFIPmtStsRpt>
    <GrpHdr>
      <MsgId>${p.id}-pacs002</MsgId>
      <CreDtTm>${dayjs().toISOString()}</CreDtTm>
    </GrpHdr>
    <OrgnlGrpInfAndSts>
      <OrgnlMsgId>${p.id}-pacs008</OrgnlMsgId>
      <OrgnlMsgNmId>pacs.008.001.02</OrgnlMsgNmId>
    </OrgnlGrpInfAndSts>
    <TxInfAndSts>
      <OrgnlEndToEndId>${p.endToEndId}</OrgnlEndToEndId>
      <TxSts>${status}</TxSts>
    </TxInfAndSts>
  </FIToFIPmtStsRpt>
</Document>`;
  res.set('Content-Type', 'application/xml').status(200).send(xml);
});

// camt.054
app.get('/payments/:id/camt054', (req, res) => {
  const p = payments.get(req.params.id);
  if (!p) return res.status(404).send('Not Found');
  const amt = majorAmount(p);
  const ns = 'urn:iso:std:iso:20022:tech:xsd:camt.054.001.04';
  const xml = `${xmlHeader(ns)}
  <BkToCstmrDbtCdtNtfctn>
    <GrpHdr>
      <MsgId>${p.id}-camt054</MsgId>
      <CreDtTm>${dayjs().toISOString()}</CreDtTm>
    </GrpHdr>
    <Ntfctn>
      <Id>${p.id}</Id>
      <NtfctnPgntn><PgNb>1</PgNb><LastPgInd>true</LastPgInd></NtfctnPgntn>
      <Ntry>
        <NtryRef>${p.id}</NtryRef>
        <Amt Ccy="${p.currency}">${amt}</Amt>
        <CdtDbtInd>CRDT</CdtDbtInd>
        <BkTxCd><Prtry>TRF</Prtry></BkTxCd>
        <NtryDtls>
          <TxDtls>
            <Refs><EndToEndId>${p.endToEndId}</EndToEndId></Refs>
            <RmtInf><Ustrd>${p.endToEndId}</Ustrd></RmtInf>
          </TxDtls>
        </NtryDtls>
      </Ntry>
    </Ntfctn>
  </BkToCstmrDbtCdtNtfctn>
</Document>`;
  res.set('Content-Type', 'application/xml').status(200).send(xml);
});

// camt.053
app.get('/statements/camt053', (_req, res) => {
  const ns = 'urn:iso:std:iso:20022:tech:xsd:camt.053.001.02';
  const all = Array.from(payments.values());
  const count = all.length;
  const sum = all.reduce((acc, p) => acc + p.amountMinor, 0) / 100;
  const xmlEntries = all.map((p) => {
    return `<Ntry>
      <Amt Ccy="${p.currency}">${(p.amountMinor/100).toFixed(2)}</Amt>
      <CdtDbtInd>CRDT</CdtDbtInd>
      <NtryRef>${p.id}</NtryRef>
      <NtryDtls>
        <TxDtls>
          <Refs><EndToEndId>${p.endToEndId}</EndToEndId></Refs>
        </TxDtls>
      </NtryDtls>
    </Ntry>`;
  }).join('\n');

  const xml = `${xmlHeader(ns)}
  <BkToCstmrStmt>
    <GrpHdr>
      <MsgId>statement-${dayjs().format('YYYYMMDDHHmmss')}</MsgId>
      <CreDtTm>${dayjs().toISOString()}</CreDtTm>
      <NbOfMsgs>${count}</NbOfMsgs>
      <CtrlSum>${(sum).toFixed(2)}</CtrlSum>
    </GrpHdr>
    <Stmt>
      <Id>${uuidv4()}</Id>
      ${xmlEntries}
    </Stmt>
  </BkToCstmrStmt>
</Document>`;
  res.set('Content-Type', 'application/xml').status(200).send(xml);
});

// Test-only reset
app.post('/__reset', (_req, res) => {
  payments.clear();
  idemKeys.clear();
  res.status(204).end();
});

const port = process.env.PORT || 3000;
app.listen(port, () => {
  console.log(`Mock API on http://localhost:${port}`);
});
JS

# tests/api
mkdir -p tests/api
cat > tests/api/conftest.py << 'PY'
import os
import requests
import pytest

BASE_URL = os.getenv("BASE_URL", "http://localhost:3000")

@pytest.fixture(autouse=True)
def reset_env():
    try:
        requests.post(f"{BASE_URL}/__reset", timeout=5)
    except Exception:
        pass
    yield
PY

cat > tests/api/test_payments_api.py << 'PY'
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
PY

# tests/api/test_iso20022_endpoints.py
cat > tests/api/test_iso20022_endpoints.py << 'PY'
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
PY

# tests/performance/create_payment.js
mkdir -p tests/performance
cat > tests/performance/create_payment.js << 'JS'
import http from 'k6/http';
import { check, sleep } from 'k6';

export const options = {
  vus: 5,
  duration: '10s',
  thresholds: {
    http_req_duration: ['p(95)<300'],
    http_req_failed: ['rate<0.01']
  }
};

const BASE_URL = __ENV.BASE_URL || 'http://localhost:3000';

export default function () {
  const payload = JSON.stringify({
    externalId: `${__VU}-${__ITER}-${Date.now()}`,
    debtorIban: 'SE12ABCDE1234567890123',
    creditorIban: 'SE34ABCDE9876543210123',
    currency: 'EUR',
    amountMinor: 1000
  });
  const headers = {
    'Content-Type': 'application/json',
    'Idempotency-Key': `${__VU}-${__ITER}`
  };
  const res = http.post(`${BASE_URL}/payments`, payload, { headers });
  check(res, {
    'status 201': (r) => r.status === 201,
    'has id': (r) => !!r.json('id'),
  });
  sleep(0.2);
}
JS

# SQL
mkdir -p sql
cat > sql/schema.sql << 'SQL'
CREATE TABLE IF NOT EXISTS payments (
  id TEXT PRIMARY KEY,
  external_id TEXT NOT NULL,
  debtor_iban TEXT NOT NULL,
  creditor_iban TEXT NOT NULL,
  currency TEXT NOT NULL,
  amount_minor INTEGER NOT NULL,
  status TEXT NOT NULL,
  created_at TIMESTAMP NOT NULL
);

CREATE TABLE IF NOT EXISTS ledger_entries (
  id TEXT PRIMARY KEY,
  payment_id TEXT NOT NULL,
  direction TEXT NOT NULL,
  amount_minor INTEGER NOT NULL,
  currency TEXT NOT NULL,
  posted_at TIMESTAMP NOT NULL
);

CREATE TABLE IF NOT EXISTS webhooks (
  id TEXT PRIMARY KEY,
  payment_id TEXT NOT NULL,
  event TEXT NOT NULL,
  delivered_at TIMESTAMP NOT NULL,
  retry_count INTEGER NOT NULL DEFAULT 0
);
SQL

cat > sql/seed.sql << 'SQL'
INSERT INTO payments (id, external_id, debtor_iban, creditor_iban, currency, amount_minor, status, created_at)
VALUES
('p1','ext-1','SE12ABCDE1234567890123','SE34ABCDE9876543210123','EUR',1000,'SETTLED', NOW()),
('p2','ext-2','SE12ABCDE1234567890123','SE34ABCDE9876543210123','EUR',2000,'SETTLED', NOW()),
('p3','ext-3','SE12ABCDE1234567890123','SE34ABCDE9876543210123','EUR',1000,'PENDING', NOW());

INSERT INTO ledger_entries (id, payment_id, direction, amount_minor, currency, posted_at)
VALUES
('l1','p1','SETTLE',1000,'EUR', NOW()),
('l2','pX','SETTLE',500,'EUR', NOW());
SQL

cat > sql/recon_queries.sql << 'SQL'
-- Settled payments missing ledger postings
SELECT p.id, p.external_id
FROM payments p
LEFT JOIN ledger_entries l
ON l.payment_id = p.id AND l.direction = 'SETTLE'
WHERE p.status = 'SETTLED' AND l.id IS NULL;

-- Potential duplicates (same debtor/creditor/amount within 5 min)
SELECT a.id AS p1, b.id AS p2, a.debtor_iban, a.creditor_iban, a.amount_minor, a.currency
FROM payments a
JOIN payments b
  ON a.debtor_iban = b.debtor_iban
 AND a.creditor_iban = b.creditor_iban
 AND a.amount_minor = b.amount_minor
 AND a.currency = b.currency
 AND a.id <> b.id
 AND ABS(EXTRACT(EPOCH FROM (a.created_at - b.created_at))) <= 300;

-- Reconcile sums between payments and ledger by currency
SELECT p.currency,
       SUM(CASE WHEN p.status='SETTLED' THEN p.amount_minor ELSE 0 END) AS settled_amount,
       SUM(CASE WHEN l.direction='SETTLE' THEN l.amount_minor ELSE 0 END) AS ledger_amount
FROM payments p
LEFT JOIN ledger_entries l ON l.payment_id = p.id
GROUP BY p.currency
HAVING SUM(CASE WHEN p.status='SETTLED' THEN p.amount_minor END)
    <> SUM(CASE WHEN l.direction='SETTLE' THEN l.amount_minor END);

-- Orphaned webhooks
SELECT w.*
FROM webhooks w
LEFT JOIN payments p ON p.id = w.payment_id
WHERE p.id IS NULL;

-- Payments stuck in PENDING > 2 hours
SELECT *
FROM payments
WHERE status='PENDING' AND created_at < NOW() - INTERVAL '2 hours';
SQL

# CI
mkdir -p .github/workflows
cat > .github/workflows/ci.yml << 'YML'
name: CI

on:
  push:
  pull_request:

jobs:
  test:
    runs-on: ubuntu-latest
    env:
      BASE_URL: http://localhost:3000
    steps:
      - uses: actions/checkout@v4

      - name: Set up Node
        uses: actions/setup-node@v4
        with:
          node-version: '18'

      - name: Install and start mock API
        working-directory: mocks/server
        run: |
          npm ci
          nohup npm start &
          sleep 2
          curl -fsS http://localhost:3000/health

      - name: Set up Python
        uses: actions/setup-python@v5
        with:
          python-version: '3.10'

      - name: Install Python deps
        run: pip install -r requirements.txt

      - name: Run API tests
        run: pytest -q

      - name: Install k6
        run: |
          sudo apt-get update
          sudo apt-get install -y gnupg software-properties-common
          curl -fsSL https://dl.k6.io/key.gpg | sudo gpg --dearmor -o /usr/share/keyrings/k6-archive-keyring.gpg
          echo "deb [signed-by=/usr/share/keyrings/k6-archive-keyring.gpg] https://dl.k6.io/deb stable main" | sudo tee /etc/apt/sources.list.d/k6.list
          sudo apt-get update
          sudo apt-get install -y k6

      - name: Performance smoke
        run: k6 run tests/performance/create_payment.js
YML

# Stage, commit, push
git add api/openapi.yaml mocks/server/package.json mocks/server/server.js \
        requirements.txt tests/api/conftest.py tests/api/test_payments_api.py tests/api/test_iso20022_endpoints.py \
        tests/performance/create_payment.js sql/schema.sql sql/seed.sql sql/recon_queries.sql \
        .github/workflows/ci.yml .gitignore

git commit -m "Add mock API, tests, OpenAPI, SQL, and CI (no README changes)"
git push -u origin setup-mock-api-and-ci

echo
echo "Open PR:"
echo "https://github.com/mmljay/corporate-payments-ba-qa-portfolio/compare/main...setup-mock-api-and-ci"
