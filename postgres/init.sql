SET client_min_messages TO WARNING;

SELECT 'CREATE DATABASE keycloak'
WHERE NOT EXISTS (
  SELECT 1 FROM pg_database WHERE datname = 'keycloak'
)\gexec

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS ch_roles (
  name VARCHAR(100) PRIMARY KEY CHECK (name ~ '^[a-zA-Z0-9_]+$'),
  description TEXT,
  policy_type VARCHAR(20) NOT NULL CHECK (policy_type IN ('permissive', 'restrictive')),
  column_grants JSONB NOT NULL DEFAULT '[]'::jsonb,
  row_filter_json JSONB,
  row_filter_sql TEXT,
  scope_event_types TEXT[],
  scope_organizations TEXT[],
  scope_risk_levels TEXT[],
  is_active BOOLEAN DEFAULT TRUE,
  created_by VARCHAR(255),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  synced_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS custom_roles (
  name VARCHAR(100) PRIMARY KEY,
  description TEXT DEFAULT '',
  notification_metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  slack_group_mention_id TEXT,
  discord_role_id TEXT,
  group_email TEXT,
  read_content_ids UUID[] DEFAULT ARRAY[]::UUID[],
  write_content_ids UUID[] DEFAULT ARRAY[]::UUID[],
  ch_role_name VARCHAR(100) REFERENCES ch_roles(name),
  sql_lab_access BOOLEAN DEFAULT FALSE,
  admin_access BOOLEAN NOT NULL DEFAULT FALSE,
  content_access VARCHAR(10) NOT NULL DEFAULT 'gamma' CHECK (content_access IN ('gamma', 'alpha', 'admin')),
  content_management BOOLEAN NOT NULL DEFAULT FALSE,
  default_dashboard_row_limit INTEGER NOT NULL DEFAULT 10000 CHECK (default_dashboard_row_limit BETWEEN 100 AND 10000),
  created_by VARCHAR(255),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  synced_keycloak_at TIMESTAMPTZ,
  synced_superset_at TIMESTAMPTZ,
  synced_ch_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS groups (
  name VARCHAR(100) PRIMARY KEY,
  description TEXT,
  notification_metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  slack_group_mention_id TEXT,
  discord_role_id TEXT,
  telegram TEXT,
  group_email TEXT,
  created_by VARCHAR(255),
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS users (
  username VARCHAR(255) PRIMARY KEY,
  keycloak_id VARCHAR(255) NOT NULL
);

CREATE TABLE IF NOT EXISTS group_members (
  group_name VARCHAR(100) REFERENCES groups(name) ON DELETE CASCADE,
  username VARCHAR(255) REFERENCES users(username) ON DELETE CASCADE,
  added_by VARCHAR(255),
  added_at TIMESTAMPTZ DEFAULT NOW(),
  PRIMARY KEY (group_name, username)
);

CREATE TABLE IF NOT EXISTS user_role_assignments (
  username VARCHAR(255) REFERENCES users(username) ON DELETE CASCADE,
  role_name VARCHAR(100) REFERENCES custom_roles(name) ON DELETE CASCADE,
  assigned_by VARCHAR(255),
  assigned_at TIMESTAMPTZ DEFAULT NOW(),
  PRIMARY KEY (username, role_name)
);

CREATE TABLE IF NOT EXISTS group_role_assignments (
  group_name VARCHAR(100) REFERENCES groups(name) ON DELETE CASCADE,
  role_name VARCHAR(100) REFERENCES custom_roles(name) ON DELETE CASCADE,
  assigned_by VARCHAR(255),
  assigned_at TIMESTAMPTZ DEFAULT NOW(),
  PRIMARY KEY (group_name, role_name)
);

CREATE TABLE IF NOT EXISTS user_ch_credentials (
  username VARCHAR(255) PRIMARY KEY REFERENCES users(username) ON DELETE CASCADE,
  ch_username VARCHAR(255) NOT NULL,
  ch_password_enc TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  last_synced_at TIMESTAMPTZ
);

INSERT INTO custom_roles (name, description, sql_lab_access, admin_access, content_access, content_management, default_dashboard_row_limit, created_by)
VALUES
  ('admin', 'Default admin role', TRUE, TRUE, 'admin', TRUE, 10000, 'system'),
  ('supervisor', 'Default supervisor role', TRUE, FALSE, 'alpha', TRUE, 10000, 'system'),
  ('analyst', 'Default analyst role', FALSE, FALSE, 'gamma', FALSE, 10000, 'system')
ON CONFLICT (name) DO NOTHING;

CREATE TABLE IF NOT EXISTS content_items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  type VARCHAR(20) NOT NULL CHECK (type IN ('chart', 'dashboard')),
  superset_id INTEGER NOT NULL,
  title VARCHAR(500) NOT NULL,
  description TEXT DEFAULT '',
  created_by VARCHAR(255),
  synced_at TIMESTAMPTZ DEFAULT NOW(),
  scope_requirements JSONB DEFAULT '{}'::jsonb,
  UNIQUE(type, superset_id)
);

CREATE TABLE IF NOT EXISTS alert_rules (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name VARCHAR(200) UNIQUE NOT NULL,
  description TEXT DEFAULT '',
  rule_type VARCHAR(20) NOT NULL DEFAULT 'direct' CHECK (rule_type IN ('direct', 'retrospective')),
  filter_sql TEXT,
  filter_json JSONB,
  query_sql TEXT,
  cron_interval_sec INTEGER DEFAULT 300,
  severity VARCHAR(20) DEFAULT 'warning',
  is_active BOOLEAN DEFAULT TRUE,
  poll_interval_sec INTEGER DEFAULT 30,
  ch_target_table TEXT,
  ch_mv_name TEXT,
  created_by VARCHAR(255),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  synced_at TIMESTAMPTZ,
  last_polled_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS notification_channels (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name VARCHAR(200) UNIQUE NOT NULL,
  apprise_url TEXT,
  is_active BOOLEAN DEFAULT TRUE,
  created_by VARCHAR(255),
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS hosted_json_endpoints (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name VARCHAR(200) NOT NULL,
  endpoint_path VARCHAR(255) UNIQUE NOT NULL,
  json_payload JSONB NOT NULL,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_by VARCHAR(255),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_by VARCHAR(255),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

INSERT INTO hosted_json_endpoints (name, endpoint_path, json_payload, is_active, created_by, updated_by)
VALUES
  ('License', 'license', '{}'::jsonb, TRUE, 'system', 'system'),
  ('Test License', 'test-license', '{}'::jsonb, TRUE, 'system', 'system')
ON CONFLICT (endpoint_path) DO NOTHING;

CREATE TABLE IF NOT EXISTS alert_rule_channels (
  rule_id UUID REFERENCES alert_rules(id) ON DELETE CASCADE,
  channel_id UUID REFERENCES notification_channels(id) ON DELETE CASCADE,
  PRIMARY KEY (rule_id, channel_id)
);

CREATE TABLE IF NOT EXISTS system_settings (
  key VARCHAR(255) PRIMARY KEY,
  value TEXT NOT NULL,
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  updated_by VARCHAR(255)
);

INSERT INTO system_settings (key, value, updated_by)
VALUES ('default_security_dashboard_cache_ttl_seconds', '63072000', 'system')
ON CONFLICT (key) DO UPDATE
SET value = EXCLUDED.value,
    updated_at = NOW(),
    updated_by = EXCLUDED.updated_by
WHERE system_settings.value = '300';
