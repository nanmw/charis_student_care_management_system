-- Run once in the Neon SQL editor before the desktop app syncs.
-- The app does not create this table.
-- Use the pooled connection string (host contains "-pooler") in Settings → Sync.

CREATE TABLE change_sets (
  seq bigserial PRIMARY KEY,
  id text NOT NULL UNIQUE,
  table_name text NOT NULL,
  record_id text NOT NULL,
  operation text NOT NULL,
  payload text NOT NULL,
  occurred_at timestamptz NOT NULL,
  user_id text NOT NULL,
  version integer NOT NULL,
  device_id text NOT NULL
);
