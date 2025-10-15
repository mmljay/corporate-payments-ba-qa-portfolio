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
