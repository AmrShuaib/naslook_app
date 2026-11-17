-- Admin accounts are ordinary users with is_admin=true (granted with ops/grant-admin.sh).
ALTER TABLE users ADD COLUMN IF NOT EXISTS is_admin boolean NOT NULL DEFAULT false;

-- Every administrative action, who did it, on what, why, and the before/after state. Rows can be added but
-- never changed or removed through the application role (trigger below); secrets/tokens are never written here.
CREATE TABLE IF NOT EXISTS audit_log(
  id bigserial PRIMARY KEY,
  at timestamptz NOT NULL DEFAULT now(),
  admin_id varchar(9) NULL REFERENCES users(id),
  actor text NOT NULL,                 -- 'user:<id>' or 'admin-key' (transition period)
  action text NOT NULL,
  target_type text NULL,
  target_id text NULL,
  reason text NULL,
  before jsonb NULL,
  after jsonb NULL,
  ip text NULL);
CREATE INDEX IF NOT EXISTS idx_audit_at ON audit_log(at DESC);

CREATE OR REPLACE FUNCTION audit_log_immutable() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN RAISE EXCEPTION 'audit_log is append-only'; END $$;
DROP TRIGGER IF EXISTS audit_log_no_change ON audit_log;
CREATE TRIGGER audit_log_no_change BEFORE UPDATE OR DELETE ON audit_log FOR EACH ROW EXECUTE FUNCTION audit_log_immutable();
