# Acceptance Criteria (summary)

## Create payment (happy path)
- Given a valid payload and an Idempotency-Key
- When I POST /payments
- Then I get 201 with id and status in {INITIATED, PENDING}

## Idempotency (same key)
- Given a successful creation with key X
- When I POST again with key X and same payload
- Then I get 201 with the same id

## Validation errors
- Given invalid currency or IBAN format
- When I POST /payments
- Then I get 400 with error details

## Cut‑off flag
- Given current time is after cut‑off
- When I create a payment
- Then scheduledNextBusinessDay is true

## ISO 20022 exports
- pain.001: MsgId, CreDtTm, EndToEndId, IBANs, InstdAmt present
- pain.002: OrgnlMsgId, OrgnlEndToEndId, TxSts present
- pacs.008: EndToEndId and InstdAmt with currency present
- pacs.002: OrgnlEndToEndId and TxSts present
- camt.053: Statement with one or more entries
- camt.054: Notification referencing the payment
```

````markdown name=docs/test-strategy.md
# Test Strategy

## Scope
- Functional API: create, get, validation, idempotency
- Scheduling flag after cut‑off
- ISO 20022 XML exports (structure checks)
- Performance smoke
- Reconciliation SQL patterns

## Approach
- API tests: pytest + requests
- XML parsing: ElementTree with namespace‑agnostic lookups
- Performance: k6 p95 latency and error rate thresholds
- SQL: example queries for duplicates and mismatches
- Traceability: map requirements to tests

## Environments
- Local mock API
- GitHub Actions CI on every push/PR

## Entry / Exit
- Entry: API healthy; dependencies installed
- Exit: Critical tests pass; no Sev1/Sev2 defects open

## Data and security
- Synthetic data only
- No PII in logs or examples

## Deliverables
- Test cases in tests/api
- Performance script in tests/performance
- CI workflow in .github/workflows/ci.yml
