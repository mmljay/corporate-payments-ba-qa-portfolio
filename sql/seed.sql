INSERT INTO payments (id, external_id, debtor_iban, creditor_iban, currency, amount_minor, status, created_at)
VALUES
('p1','ext-1','SE12ABCDE1234567890123','SE34ABCDE9876543210123','EUR',1000,'SETTLED', NOW()),
('p2','ext-2','SE12ABCDE1234567890123','SE34ABCDE9876543210123','EUR',2000,'SETTLED', NOW()),
('p3','ext-3','SE12ABCDE1234567890123','SE34ABCDE9876543210123','EUR',1000,'PENDING', NOW());

INSERT INTO ledger_entries (id, payment_id, direction, amount_minor, currency, posted_at)
VALUES
('l1','p1','SETTLE',1000,'EUR', NOW()),
('l2','pX','SETTLE',500,'EUR', NOW());
