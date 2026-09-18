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
  extension_inventory_access BOOLEAN DEFAULT FALSE,
  admin_access BOOLEAN NOT NULL DEFAULT FALSE,
  trial_access BOOLEAN NOT NULL DEFAULT FALSE,
  content_access VARCHAR(10) NOT NULL DEFAULT 'gamma' CHECK (content_access IN ('gamma', 'alpha', 'admin')),
  content_management BOOLEAN NOT NULL DEFAULT FALSE,
  export_api_access BOOLEAN NOT NULL DEFAULT FALSE,
  sensitive_data_decryption BOOLEAN NOT NULL DEFAULT FALSE,
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

INSERT INTO ch_roles (name, description, policy_type, column_grants, created_by)
VALUES
  ('__role_supervisor', 'Managed policy for role supervisor', 'permissive', '["schema","event_utc_ms","browser_uuid","event_uuid","event_type","tab_url","tab_id","hostname","frame_url","event_source","session_id","metadata","browser_name","browser_version","browser_os","browser_os_version","browser_extension_version","browser_vulnerability_count","browser_vulnerability_checked_utc_ms","browser_profile_email","browser_profile_id","browser_local_ip","browser_ext_configuration_id","browser_computer_name","browser_computer_mac_address","browser_computer_serial_number","ctx_reputation","ctx_organization","ctx_is_new_domain","ctx_url_context","ctx_url_tags","ctx_ip","ctx_referrer","ctx_referred_by_search","ctx_referrer_chain","ctx_considered_ai_site","ctx_considered_hosting_site","ctx_unfamiliar_domain","ctx_page_title","risk_type","risk_level","risk_rationale","risk_context","verdicts","action","secondary_url","intercept_matches","intercept_context","files","content_snippet","content_length","user_gesture","user_gesture_utc_ms","indicators","threats","script_attribution","_ingest_time_utc_ms"]'::jsonb, 'system'),
  ('__role_analyst', 'Managed policy for role analyst', 'permissive', '["schema","event_utc_ms","browser_uuid","event_uuid","event_type","tab_url","tab_id","hostname","frame_url","event_source","session_id","metadata","browser_name","browser_version","browser_os","browser_os_version","browser_extension_version","browser_vulnerability_count","browser_vulnerability_checked_utc_ms","browser_profile_email","browser_profile_id","browser_local_ip","browser_ext_configuration_id","browser_computer_name","browser_computer_mac_address","browser_computer_serial_number","ctx_reputation","ctx_organization","ctx_is_new_domain","ctx_url_context","ctx_url_tags","ctx_ip","ctx_referrer","ctx_referred_by_search","ctx_referrer_chain","ctx_considered_ai_site","ctx_considered_hosting_site","ctx_unfamiliar_domain","ctx_page_title","risk_type","risk_level","risk_rationale","risk_context","verdicts","action","secondary_url","intercept_matches","intercept_context","files","content_snippet","content_length","user_gesture","user_gesture_utc_ms","indicators","threats","script_attribution","_ingest_time_utc_ms"]'::jsonb, 'system')
ON CONFLICT (name) DO NOTHING;

INSERT INTO custom_roles (name, description, sql_lab_access, extension_inventory_access, admin_access, content_access, content_management, export_api_access, sensitive_data_decryption, ch_role_name, default_dashboard_row_limit, created_by)
VALUES
  ('admin', 'Default admin role', TRUE, TRUE, TRUE, 'admin', TRUE, TRUE, TRUE, NULL, 10000, 'system'),
  ('supervisor', 'Default supervisor role', TRUE, TRUE, FALSE, 'alpha', TRUE, FALSE, FALSE, '__role_supervisor', 10000, 'system'),
  ('analyst', 'Default analyst role', FALSE, FALSE, FALSE, 'gamma', FALSE, FALSE, FALSE, '__role_analyst', 10000, 'system')
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
  enrollment_required BOOLEAN NOT NULL DEFAULT TRUE,
  created_by VARCHAR(255),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_by VARCHAR(255),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

INSERT INTO hosted_json_endpoints (name, endpoint_path, json_payload, is_active, created_by, updated_by)
VALUES
  ('License', 'license', '{}'::jsonb, TRUE, 'system', 'system'),
  ('Test License', 'test_license', '{}'::jsonb, TRUE, 'system', 'system')
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

CREATE TABLE IF NOT EXISTS extension_store_metadata (
  store_key VARCHAR(32) NOT NULL,
  extension_id VARCHAR(255) NOT NULL,
  extension_name TEXT DEFAULT '',
  store_url TEXT DEFAULT '',
  icon_url TEXT DEFAULT '',
  metadata_source_url TEXT DEFAULT '',
  fetch_status VARCHAR(20) NOT NULL DEFAULT 'missing',
  last_error TEXT DEFAULT '',
  fetched_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (store_key, extension_id)
);

CREATE TABLE IF NOT EXISTS email_verification_tokens (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  username VARCHAR(255) NOT NULL REFERENCES users(username) ON DELETE CASCADE,
  email VARCHAR(320) NOT NULL,
  token_hash CHAR(64) NOT NULL UNIQUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  expires_at TIMESTAMPTZ NOT NULL,
  used_at TIMESTAMPTZ NULL,
  purpose VARCHAR(32) NOT NULL DEFAULT 'verify'
);

CREATE INDEX IF NOT EXISTS idx_email_verification_tokens_username ON email_verification_tokens (username);

CREATE TABLE IF NOT EXISTS password_reset_tokens (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  username VARCHAR(255) NOT NULL REFERENCES users(username) ON DELETE CASCADE,
  email VARCHAR(320) NOT NULL,
  token_hash CHAR(64) NOT NULL UNIQUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  expires_at TIMESTAMPTZ NOT NULL,
  used_at TIMESTAMPTZ NULL
);

CREATE INDEX IF NOT EXISTS idx_password_reset_tokens_username ON password_reset_tokens (username);

INSERT INTO system_settings (key, value, updated_by)
VALUES ('default_security_dashboard_cache_ttl_seconds', '300', 'system')
ON CONFLICT (key) DO UPDATE
SET value = EXCLUDED.value,
    updated_at = NOW(),
    updated_by = EXCLUDED.updated_by
WHERE system_settings.value = '63072000';
