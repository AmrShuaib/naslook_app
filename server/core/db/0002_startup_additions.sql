-- Everything the server used to create at startup (all idempotent), now applied once through migrate.js.
-- On the production database these are no-ops because the objects already exist.

CREATE TABLE IF NOT EXISTS stories(
  id uuid PRIMARY KEY,
  user_id varchar(9) NOT NULL REFERENCES users(id),
  type varchar(10) NOT NULL,
  content text NOT NULL,
  caption text NOT NULL DEFAULT '',
  lat double precision NOT NULL,
  lng double precision NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL);

CREATE TABLE IF NOT EXISTS blocks(
  blocker_id varchar(9) NOT NULL REFERENCES users(id),
  blocked_id varchar(9) NOT NULL REFERENCES users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (blocker_id, blocked_id));

CREATE TABLE IF NOT EXISTS reports(
  id uuid PRIMARY KEY,
  reporter_id varchar(9) NOT NULL REFERENCES users(id),
  reported_id varchar(9) NOT NULL REFERENCES users(id),
  reason varchar(20) NOT NULL,
  message_id uuid NULL,
  details text NOT NULL DEFAULT '',
  created_at timestamptz NOT NULL DEFAULT now(),
  status varchar(12) NOT NULL DEFAULT 'new');

CREATE TABLE IF NOT EXISTS request_ignores(
  user_id varchar(9) NOT NULL REFERENCES users(id),
  peer_id varchar(9) NOT NULL REFERENCES users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, peer_id));

CREATE TABLE IF NOT EXISTS vessels(
  id uuid PRIMARY KEY,
  name varchar(60) NOT NULL,
  topic varchar(60) NOT NULL,
  description text NOT NULL DEFAULT '',
  owner_id varchar(9) NOT NULL REFERENCES users(id),
  cover_url text NULL,
  is_public boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now());

CREATE TABLE IF NOT EXISTS vessel_members(
  vessel_id uuid NOT NULL REFERENCES vessels(id) ON DELETE CASCADE,
  user_id varchar(9) NOT NULL REFERENCES users(id),
  role varchar(10) NOT NULL DEFAULT 'member',
  joined_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (vessel_id, user_id));

CREATE TABLE IF NOT EXISTS posts(
  id uuid PRIMARY KEY,
  vessel_id uuid NOT NULL REFERENCES vessels(id) ON DELETE CASCADE,
  author_id varchar(9) NOT NULL REFERENCES users(id),
  type varchar(10) NOT NULL,
  content text NOT NULL,
  caption text NOT NULL DEFAULT '',
  created_at timestamptz NOT NULL DEFAULT now());

CREATE TABLE IF NOT EXISTS comments(
  id uuid PRIMARY KEY,
  post_id uuid NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
  author_id varchar(9) NOT NULL REFERENCES users(id),
  text text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now());

CREATE TABLE IF NOT EXISTS supports(
  post_id uuid NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
  user_id varchar(9) NOT NULL REFERENCES users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (post_id, user_id));

CREATE TABLE IF NOT EXISTS profiles(
  user_id varchar(9) PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  bio text NOT NULL DEFAULT '',
  voice_intro_url text NULL,
  skills jsonb NOT NULL DEFAULT '[]',
  hobbies jsonb NOT NULL DEFAULT '[]',
  looking_for jsonb NOT NULL DEFAULT '[]',
  offerings jsonb NOT NULL DEFAULT '[]',
  account_type varchar(10) NOT NULL DEFAULT 'personal',
  visibility jsonb NOT NULL DEFAULT '{}',
  is_public boolean NOT NULL DEFAULT true,
  updated_at timestamptz NOT NULL DEFAULT now());

CREATE TABLE IF NOT EXISTS map_presence(
  user_id varchar(9) PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  lat double precision NOT NULL,
  lng double precision NOT NULL,
  title varchar(60) NULL,
  visible boolean NOT NULL DEFAULT false,
  updated_at timestamptz NOT NULL DEFAULT now());

CREATE TABLE IF NOT EXISTS map_pins(
  id uuid PRIMARY KEY,
  owner_id varchar(9) NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  lat double precision NOT NULL,
  lng double precision NOT NULL,
  type varchar(10) NOT NULL,
  content text NOT NULL,
  place_name varchar(80) NULL,
  rating smallint NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NULL);

CREATE TABLE IF NOT EXISTS districts(
  id serial PRIMARY KEY,
  city varchar(20) NOT NULL DEFAULT 'jeddah',
  osm_id varchar(20) UNIQUE,
  name_ar varchar(80) NOT NULL,
  name_en varchar(80) NULL,
  lat double precision NOT NULL,
  lng double precision NOT NULL,
  vessel_id uuid NULL REFERENCES vessels(id));

CREATE TABLE IF NOT EXISTS businesses(
  id uuid PRIMARY KEY,
  owner_id varchar(9) NOT NULL REFERENCES users(id),
  name varchar(80) NOT NULL,
  category varchar(30) NOT NULL,
  description text NOT NULL DEFAULT '',
  lat double precision NOT NULL,
  lng double precision NOT NULL,
  address varchar(160) NULL,
  phone varchar(30) NULL,
  hours varchar(120) NULL,
  cover_url text NULL,
  verified boolean NOT NULL DEFAULT false,
  status varchar(12) NOT NULL DEFAULT 'pending',
  vessel_id uuid NULL REFERENCES vessels(id),
  created_at timestamptz NOT NULL DEFAULT now());

CREATE TABLE IF NOT EXISTS push_subscriptions(
  endpoint text PRIMARY KEY,
  user_id varchar(9) NOT NULL REFERENCES users(id),
  subscription jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now());

CREATE TABLE IF NOT EXISTS vessel_bans(
  vessel_id uuid NOT NULL REFERENCES vessels(id) ON DELETE CASCADE,
  user_id varchar(9) NOT NULL REFERENCES users(id),
  by_id varchar(9) NOT NULL REFERENCES users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (vessel_id, user_id));

CREATE INDEX IF NOT EXISTS idx_stories_expires ON stories(expires_at);

ALTER TABLE messages ADD COLUMN IF NOT EXISTS delivered_at timestamptz;

ALTER TABLE messages ADD COLUMN IF NOT EXISTS read_at timestamptz;

CREATE INDEX IF NOT EXISTS idx_posts_vessel ON posts(vessel_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_comments_post ON comments(post_id, created_at);

ALTER TABLE map_presence ADD COLUMN IF NOT EXISTS hide_after_hours int NULL;

ALTER TABLE map_presence ADD COLUMN IF NOT EXISTS expires_at timestamptz NULL;

CREATE INDEX IF NOT EXISTS idx_map_pins_geo ON map_pins(lat, lng);

ALTER TABLE vessels ADD COLUMN IF NOT EXISTS kind varchar(12) NOT NULL DEFAULT 'general';

ALTER TABLE vessels ADD COLUMN IF NOT EXISTS district_id integer NULL;

ALTER TABLE vessels ADD COLUMN IF NOT EXISTS business_id uuid NULL;

ALTER TABLE vessels ADD COLUMN IF NOT EXISTS lat double precision NULL;

ALTER TABLE vessels ADD COLUMN IF NOT EXISTS lng double precision NULL;

ALTER TABLE posts ADD COLUMN IF NOT EXISTS kind varchar(12) NOT NULL DEFAULT 'discussion';

ALTER TABLE posts ADD COLUMN IF NOT EXISTS tag varchar(16) NULL;

ALTER TABLE vessel_members ADD COLUMN IF NOT EXISTS last_read_at timestamptz NOT NULL DEFAULT now();

ALTER TABLE vessel_members ADD COLUMN IF NOT EXISTS muted boolean NOT NULL DEFAULT false;

ALTER TABLE users ADD COLUMN IF NOT EXISTS district_id integer NULL;

ALTER TABLE users ADD COLUMN IF NOT EXISTS last_seen timestamptz;

ALTER TABLE users ADD COLUMN IF NOT EXISTS avatar_url text;

CREATE INDEX IF NOT EXISTS idx_msg_unread ON messages(recipient_id, sender_id) WHERE read_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_msg_sent_at ON messages(sent_at);

ALTER TABLE sessions ADD COLUMN IF NOT EXISTS id uuid NOT NULL DEFAULT gen_random_uuid();

ALTER TABLE sessions ADD COLUMN IF NOT EXISTS user_agent text NULL;

ALTER TABLE sessions ADD COLUMN IF NOT EXISTS last_used_at timestamptz NULL;

CREATE INDEX IF NOT EXISTS idx_sessions_user ON sessions(user_id);
