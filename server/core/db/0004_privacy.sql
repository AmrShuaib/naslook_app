-- Notification previews are off by default ("رسالة جديدة"); the user can opt in.
ALTER TABLE users ADD COLUMN IF NOT EXISTS push_preview boolean NOT NULL DEFAULT false;
-- Deleted accounts are anonymised in place (the row must stay for foreign keys); this marks them.
ALTER TABLE users ADD COLUMN IF NOT EXISTS deleted_at timestamptz NULL;
