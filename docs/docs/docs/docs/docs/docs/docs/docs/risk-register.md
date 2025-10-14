# Risk Register (summary)

- Duplicate processing on retries
  - Mitigation: enforce Idempotency-Key; test same‑key behavior
- Weak validation causes bad data
  - Mitigation: strict checks and negative tests
- Cut‑off edge cases
  - Mitigation: simple rule + tests; document behavior
- Low observability during incidents
  - Mitigation: clean logs, reproducible inputs, IDs in responses
