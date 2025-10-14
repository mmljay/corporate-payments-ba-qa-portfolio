# PRD — Corporate Credit Transfer

## Problem
Users need a clean API to create payments safely, read status, and extract basic information for reconciliation and reports.

## Functional requirements
- Create Payment (externalId, debtorIban, creditorIban, currency, amountMinor)
- Idempotency via Idempotency-Key header
- Get Payment by id
- Scheduling flag when after cut‑off

## Non‑functional requirements
- Validation: formats, required fields, positive amounts
- Observability: clean logs (no PII)
- Performance: baseline latency and error rate
- Testability: mockable and deterministic

## Acceptance criteria
See docs/acceptance-criteria.md

## Assumptions
- Synthetic data is acceptable
- Simple status flow: INITIATED → PENDING

## Constraints
- Minimal in-memory storage in mock
- ISO 20022 XML is simplified (structure only)
