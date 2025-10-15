# Corporate Payments — BA + QA Portfolio (Credit Transfer & Reconciliation)

[![Python](https://img.shields.io/badge/Python-3.10+-blue)](https://www.python.org/)
[![Node.js](https://img.shields.io/badge/Node.js-18+-green)](https://nodejs.org/)
[![CI](https://img.shields.io/github/actions/workflow/status/jayawardenamml/corporate-payments-ba-qa-portfolio/ci.yml?label=CI)](https://github.com/mmljay/corporate-payments-ba-qa-portfolio/actions)

This project demonstrates my end-to-end Business Analysis (BA) and Quality Assurance (QA) skills, focusing on credit transfer functionality and reconciliation processes. It combines comprehensive BA documentation with hands-on QA deliverables, supported by a minimal payments API mock that can run locally or in CI pipelines.

---

## What’s inside

- Business Analysis
  - BRD/PRD, stakeholder map and RACI
  - Personas, BPMN‑style flows
  - Backlog, user stories, acceptance criteria
  - UAT plan, risks, and KPIs

- Quality Assurance
  - Test strategy and plan
  - Automated API tests (pytest)
  - Performance smoke (k6)
  - Reconciliation SQL checks

- Payments scope
  - Create and get payment
  - Idempotency
  - Simple cut‑off flag (schedule next day)
  - ISO 20022 exports (simplified)

---

## Quick start

Prerequisites: Node.js 18+, Python 3.10+, pip

1) Start the mock API
- cd mocks/server
- npm ci
- npm start
- Health: http://localhost:3000/health

2) Run tests
- pip install -r requirements.txt
- pytest -q

3) Optional: performance smoke
- Install k6: https://k6.io/docs/get-started/installation/
- k6 run tests/performance/create_payment.js

---

## ISO 20022 messages (simplified)

| Endpoint | Message | Key elements |
|---|---|---|
| GET /payments/{id}/pain001 | pain.001 | MsgId, CreDtTm, EndToEndId, IBANs, InstdAmt |
| GET /payments/{id}/pain002 | pain.002 | OrgnlMsgId, OrgnlEndToEndId, TxSts |
| GET /payments/{id}/pacs008 | pacs.008 | EndToEndId, InstdAmt, Accounts |
| GET /payments/{id}/pacs002 | pacs.002 | OrgnlEndToEndId, TxSts |
| GET /payments/{id}/camt054 | camt.054 | NtryRef, Amt, EndToEndId |
| GET /statements/camt053 | camt.053 | Header + entries (Ntry) |

Notes:
- XML is minimal for clarity.
- Status maps to ACSP unless rejected.

---

## Sample usage

Create a payment
```bash
curl -X POST http://localhost:3000/payments \
  -H "Content-Type: application/json" \
  -H "Idempotency-Key: 123e4567" \
  -d '{
    "externalId":"ext-001",
    "debtorIban":"SE12ABCDE1234567890123",
    "creditorIban":"SE34ABCDE9876543210123",
    "currency":"EUR",
    "amountMinor":15000
  }'
```

Export a pain.001
```bash
curl http://localhost:3000/payments/{id}/pain001
```

---

## Repository structure

```text
docs/
  brd.md
  prd.md
  stakeholders-and-raci.md
  process-flows-bpmn.md
  user-personas.md
  user-stories-and-backlog.md
  acceptance-criteria.md
  uat-plan.md
  test-strategy.md
  test-plan.md
  traceability-matrix.md
  risk-register.md
  metrics-and-kpis.md
  architecture.md
  iso20022-overview.md
  iso20022-mapping.md
api/
  openapi.yaml
mocks/server/
  package.json
  server.js
tests/
  api/ (pytest)
  performance/ (k6)
sql/
  schema.sql
  seed.sql
  recon_queries.sql
.github/workflows/
  ci.yml
requirements.txt
```

---

## How I worked (BA)

- Defined the problem and outcomes (BRD/PRD)
- Mapped stakeholders and roles (RACI)
- Wrote clear user stories with acceptance criteria
- Modeled flows for clarity
- Planned UAT and set KPIs and risks

## How I tested (QA)

- Covered happy paths, validation, and idempotency
- Checked a simple cut‑off flag
- Parsed ISO 20022 XML in tests
- Ran a small k6 performance smoke
- Added SQL checks for reconciliation patterns

---

## Traceability and CI

- Requirements map to test cases (see docs/traceability-matrix.md)
- CI runs on every push with GitHub Actions

---

## Author

- GitHub: [mmljay](https://github.com/mmljay)
