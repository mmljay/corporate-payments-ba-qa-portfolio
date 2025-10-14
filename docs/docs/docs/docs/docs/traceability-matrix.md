# Traceability Matrix

| Requirement | Tests |
|---|---|
| R1 Create Payment | tests/api/test_payments_api.py::test_create_payment_success |
| R2 Validation | tests/api/test_payments_api.py::test_validation_errors |
| R3 Idempotency | tests/api/test_payments_api.py::test_idempotency_same_key_returns_same_resource |
| R4 Get Status | tests/api/test_payments_api.py::test_get_status |
| R5 Cut‑off Flag | tests/api/test_payments_api.py::test_cutoff_logic_flag_present |
| R6 ISO Exports | tests/api/test_iso20022_endpoints.py::* |
