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
