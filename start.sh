#!/usr/bin/env bash

set -euo pipefail

GREEN=$'\033[1;32m'
CYAN=$'\033[1;36m'
BOLD=$'\033[1m'
DIM=$'\033[2m'
RESET=$'\033[0m'
SEKANT_DASHBOARD_VERSION="1.1.8"

echo -e "${GREEN}"
cat << "EOF"

   ███████╗███████╗██╗  ██╗ █████╗ ███╗   ██╗████████╗
   ██╔════╝██╔════╝██║ ██╔╝██╔══██╗████╗  ██║╚══██╔══╝
   ███████╗█████╗  █████╔╝ ███████║██╔██╗ ██║   ██║
   ╚════██║██╔══╝  ██╔═██╗ ██╔══██║██║╚██╗██║   ██║
   ███████║███████╗██║  ██╗██║  ██║██║ ╚████║   ██║
   ╚══════╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═══╝   ╚═╝

   ███████╗███████╗ ██████╗██╗   ██╗██████╗ ██╗████████╗██╗   ██╗
   ██╔════╝██╔════╝██╔════╝██║   ██║██╔══██╗██║╚══██╔══╝╚██╗ ██╔╝
   ███████╗█████╗  ██║     ██║   ██║██████╔╝██║   ██║    ╚████╔╝
   ╚════██║██╔══╝  ██║     ██║   ██║██╔══██╗██║   ██║     ╚██╔╝
   ███████║███████╗╚██████╗╚██████╔╝██║  ██║██║   ██║      ██║
   ╚══════╝╚══════╝ ╚═════╝ ╚═════╝ ╚═╝  ╚═╝╚═╝   ╚═╝      ╚═╝

EOF
if [[ -n "${SEKANT_DASHBOARD_VERSION}" ]]; then
  echo
  echo -e "${CYAN}${BOLD}Sekant Management Console v${SEKANT_DASHBOARD_VERSION}${RESET}"
  echo
  echo -e "${GREEN}${BOLD}Starting Sekant Management Console Platform${RESET}"
  echo
fi
echo -e "${RESET}"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root_dir="${script_dir}"
if [[ ! -f "${root_dir}/docker-compose.yml" && -f "${root_dir}/../docker-compose.yml" ]]; then
  root_dir="$(cd "${root_dir}/.." && pwd)"
fi
if [[ ! -f "${root_dir}/docker-compose.yml" ]]; then
  echo -e "${CYAN}${BOLD}Error:${RESET} Could not find docker-compose.yml next to start.sh." >&2
  echo "Run start.sh from the extracted build folder (or move start.sh next to docker-compose.yml)." >&2
  exit 1
fi
env_file="${root_dir}/.env"
storage_dir="${root_dir}/clickhouse/config.d"
force_reconfigure=0
upgrade=0
verbose=0
quiet=0
upgrade_log_file=""
compose_up_args=()
github_owner="${SEKANT_GITHUB_OWNER:-rishi-sekantsec}"
github_repo="${SEKANT_GITHUB_REPO:-management-console}"

nginx_conf_path="${root_dir}/nginx/nginx.conf"

http_get_to_file() {
  local url="$1"
  local out="$2"

  if command -v curl >/dev/null 2>&1; then
    if [[ "$url" == "https://api.github.com/"* && -n "${GITHUB_TOKEN:-}" ]]; then
      curl -fsSL -H "Authorization: Bearer ${GITHUB_TOKEN}" -H "X-GitHub-Api-Version: 2022-11-28" -o "$out" "$url"
      return $?
    fi
    curl -fsSL -o "$out" "$url"
    return $?
  fi
  if command -v wget >/dev/null 2>&1; then
    wget -q -O "$out" "$url"
    return $?
  fi
  return 127
}

github_last_api_url=""
github_last_api_status=""
github_last_api_message=""
github_candidate_tag=""
github_latest_tag_value=""

github_api_get_to_file() {
  local url="$1"
  local out="$2"
  github_last_api_url="$url"
  github_last_api_status=""
  github_last_api_message=""

  if command -v curl >/dev/null 2>&1; then
    local status
    if [[ -n "${GITHUB_TOKEN:-}" ]]; then
      status="$(curl -sSL -H "Authorization: Bearer ${GITHUB_TOKEN}" -H "X-GitHub-Api-Version: 2022-11-28" -o "$out" -w "%{http_code}" "$url" || true)"
    else
      status="$(curl -sSL -o "$out" -w "%{http_code}" "$url" || true)"
    fi
    github_last_api_status="$status"
    if [[ "$status" != "200" ]]; then
      github_last_api_message="$(grep -oE '"message"[[:space:]]*:[[:space:]]*"[^"]+"' "$out" | head -n 1 | sed -E 's/.*"message"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/' || true)"
      return 1
    fi
    return 0
  fi

  if command -v wget >/dev/null 2>&1; then
    if wget -q -O "$out" "$url"; then
      github_last_api_status="200"
      return 0
    fi
    github_last_api_status="0"
    return 1
  fi

  github_last_api_status="0"
  return 127
}

normalize_version() {
  local v
  v="$(printf "%s" "${1:-}" | tr -d ' \t\r\n')"
  v="${v#v}"
  printf "%s" "$v"
}

semver_gt() {
  local a b
  a="$(normalize_version "${1:-}")"
  b="$(normalize_version "${2:-}")"
  if [[ -z "$a" || -z "$b" ]]; then
    return 1
  fi
  local a1 a2 a3 b1 b2 b3
  IFS='.' read -r a1 a2 a3 <<<"$a"
  IFS='.' read -r b1 b2 b3 <<<"$b"
  a1="${a1:-0}"; a2="${a2:-0}"; a3="${a3:-0}"
  b1="${b1:-0}"; b2="${b2:-0}"; b3="${b3:-0}"
  if (( a1 != b1 )); then (( a1 > b1 )); return $?; fi
  if (( a2 != b2 )); then (( a2 > b2 )); return $?; fi
  if (( a3 != b3 )); then (( a3 > b3 )); return $?; fi
  return 1
}

script_file_version() {
  local f="$1"
  if [[ ! -f "$f" ]]; then
    printf "%s" ""
    return 0
  fi
  local line v
  line="$(grep -m 1 '^SEKANT_DASHBOARD_VERSION=' "$f" 2>/dev/null || true)"
  v="$(printf "%s" "$line" | sed -E 's/^SEKANT_DASHBOARD_VERSION="([^"]*)".*$/\1/' | tr -d ' \t\r\n')"
  printf "%s" "$(normalize_version "$v")"
}

if [[ "${BASH_SOURCE[0]}" != *"start.sh.new" ]]; then
  new_script="${root_dir}/start.sh.new"
  if [[ -f "$new_script" && -z "${SEKANT_NO_CHAIN_TO_NEW:-}" ]]; then
    v_new="$(script_file_version "$new_script")"
    v_cur="$(script_file_version "${root_dir}/start.sh")"
    if [[ -z "$v_cur" || -z "$v_new" ]] || semver_gt "$v_new" "$v_cur"; then
      exec "$new_script" "$@"
    fi
  fi
fi

tag_semver() {
  local tag="$1"
  tag="$(printf "%s" "${tag:-}" | tr -d ' \t\r\n')"
  tag="${tag#refs/tags/}"
  if [[ "$tag" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    printf "%s" "$(normalize_version "$tag")"
    return 0
  fi
  if [[ "$tag" =~ (v?[0-9]+\.[0-9]+\.[0-9]+) ]]; then
    printf "%s" "$(normalize_version "${BASH_REMATCH[1]}")"
    return 0
  fi
  printf "%s" ""
  return 0
}

github_latest_release_tag() {
  local api_url tmp tag
  api_url="https://api.github.com/repos/${github_owner}/${github_repo}/releases/latest"
  tmp="$(mktemp)"
  if ! github_api_get_to_file "$api_url" "$tmp" >/dev/null 2>&1; then
    rm -f "$tmp" >/dev/null 2>&1 || true
    return 1
  fi
  tag="$(grep -oE '"tag_name"[[:space:]]*:[[:space:]]*"[^"]+"' "$tmp" | head -n 1 | sed -E 's/.*"tag_name"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/')"
  rm -f "$tmp" >/dev/null 2>&1 || true
  if [[ -z "$tag" ]]; then
    return 1
  fi
  github_candidate_tag="$tag"
  return 0
}

github_highest_semver_tag() {
  local page=1
  local pages_left=5
  local best_tag=""
  local best_semver=""

  while (( pages_left > 0 )); do
    local api_url tmp body_tag
    api_url="https://api.github.com/repos/${github_owner}/${github_repo}/tags?per_page=100&page=${page}"
    tmp="$(mktemp)"
    if ! github_api_get_to_file "$api_url" "$tmp" >/dev/null 2>&1; then
      rm -f "$tmp" >/dev/null 2>&1 || true
      break
    fi

    if grep -qE '^[[:space:]]*\[[[:space:]]*\][[:space:]]*$' "$tmp"; then
      rm -f "$tmp" >/dev/null 2>&1 || true
      break
    fi

    while IFS= read -r body_tag; do
      [[ -z "$body_tag" ]] && continue
      local semver
      semver="$(tag_semver "$body_tag")"
      [[ -z "$semver" ]] && continue
      if [[ -z "$best_semver" ]] || semver_gt "$semver" "$best_semver"; then
        best_semver="$semver"
        best_tag="$body_tag"
      fi
    done < <(sed -nE 's/.*"name"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' "$tmp")

    rm -f "$tmp" >/dev/null 2>&1 || true

    page=$(( page + 1 ))
    pages_left=$(( pages_left - 1 ))
  done

  if [[ -z "$best_tag" ]]; then
    return 1
  fi
  github_candidate_tag="$best_tag"
  return 0
}

github_highest_semver_tag_via_git() {
  if ! command -v git >/dev/null 2>&1; then
    return 1
  fi

  local repo_url="https://github.com/${github_owner}/${github_repo}.git"
  local best_tag=""
  local best_semver=""
  local line ref tag semver

  while IFS= read -r line; do
    ref="${line##*$'\t'}"
    tag="${ref#refs/tags/}"
    semver="$(tag_semver "$tag")"
    [[ -z "$semver" ]] && continue
    if [[ -z "$best_semver" ]] || semver_gt "$semver" "$best_semver"; then
      best_semver="$semver"
      best_tag="$tag"
    fi
  done < <(GIT_TERMINAL_PROMPT=0 git ls-remote --tags --refs "$repo_url" 2>/dev/null || true)

  if [[ -z "$best_tag" ]]; then
    return 1
  fi
  github_candidate_tag="$best_tag"
  return 0
}

github_latest_tag() {
  github_latest_tag_value=""
  github_candidate_tag=""
  if github_latest_release_tag; then
    github_latest_tag_value="$github_candidate_tag"
    return 0
  fi
  if github_highest_semver_tag; then
    github_latest_tag_value="$github_candidate_tag"
    return 0
  fi
  if github_highest_semver_tag_via_git; then
    github_latest_tag_value="$github_candidate_tag"
    return 0
  fi
  return 1
}

detect_repo_prefix() {
  local tag="$1"
  local tmp url
  tmp="$(mktemp)"
  url="https://raw.githubusercontent.com/${github_owner}/${github_repo}/${tag}/docker-compose.yml"
  if http_get_to_file "$url" "$tmp" >/dev/null 2>&1; then
    rm -f "$tmp" >/dev/null 2>&1 || true
    printf "%s" ""
    return 0
  fi
  url="https://raw.githubusercontent.com/${github_owner}/${github_repo}/${tag}/dashboard/docker-compose.yml"
  if http_get_to_file "$url" "$tmp" >/dev/null 2>&1; then
    rm -f "$tmp" >/dev/null 2>&1 || true
    printf "%s" "dashboard/"
    return 0
  fi
  rm -f "$tmp" >/dev/null 2>&1 || true
  return 1
}

apply_update_from_github() {
  local tag="$1"
  local prefix
  if ! prefix="$(detect_repo_prefix "$tag")"; then
    return 1
  fi

  local files=(
    "start.sh"
    "docker-compose.yml"
    "clickhouse/config.xml"
    "clickhouse/init.sql"
    "clickhouse/init.remote.sql"
    "clickhouse/storage.local.xml"
    "clickhouse/storage.remote.xml"
    "clickhouse/config.d/storage.xml"
    "postgres/init.sql"
  )

  local f url tmp dest_dir dest
  for f in "${files[@]}"; do
    url="https://raw.githubusercontent.com/${github_owner}/${github_repo}/${tag}/${prefix}${f}"
    tmp="$(mktemp)"
    if ! http_get_to_file "$url" "$tmp" >/dev/null 2>&1; then
      rm -f "$tmp" >/dev/null 2>&1 || true
      echo -e "${CYAN}${BOLD}Error:${RESET} Failed to download ${f} from ${url}" >&2
      return 1
    fi
    if [[ "$f" == "start.sh" ]]; then
      dest="${root_dir}/start.sh.new"
    else
      dest="${root_dir}/${f}"
    fi
    dest_dir="$(dirname "$dest")"
    mkdir -p "$dest_dir"
    if ! mv "$tmp" "$dest" >/dev/null 2>&1; then
      if cp "$tmp" "$dest" >/dev/null 2>&1; then
        rm -f "$tmp" >/dev/null 2>&1 || true
      else
        rm -f "$tmp" >/dev/null 2>&1 || true
        echo -e "${CYAN}${BOLD}Error:${RESET} Failed to write ${dest}" >&2
        return 1
      fi
    fi
  done

  chmod +x "${root_dir}/start.sh.new" >/dev/null 2>&1 || true
  return 0
}

check_for_github_update() {
  local latest_tag latest current
  latest_tag=""
  if github_latest_tag; then
    latest_tag="$github_latest_tag_value"
  fi
  if [[ -z "${latest_tag:-}" ]]; then
    return 0
  fi
  latest="$(tag_semver "$latest_tag")"
  if [[ -z "$latest" ]]; then
    latest="$(normalize_version "$latest_tag")"
  fi
  current="$(normalize_version "${SEKANT_DASHBOARD_VERSION:-}")"

  if [[ -z "$current" ]]; then
    if (( quiet == 0 )); then
      echo -e "${CYAN}${BOLD}Notice:${RESET} Latest available version is ${latest} (run ./start.sh --upgrade to upgrade)."
    fi
    return 0
  fi

  if semver_gt "$latest" "$current"; then
    if (( quiet == 0 )); then
      echo -e "${CYAN}${BOLD}Update available:${RESET} v${current} -> v${latest}"
      echo "Run ./start.sh --upgrade to upgrade to the latest version."
      echo "Docker images are available at: https://hub.docker.com/r/sekantsec/management-console"
      echo "Distribution sources: https://github.com/${github_owner}/${github_repo}"
    fi
  fi
}

write_postgres_init_sql() {
  mkdir -p "${root_dir}/postgres"
  cat > "${root_dir}/postgres/init.sql" <<'EOF'
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
EOF
}

postgres_init_path="${root_dir}/postgres/init.sql"
if [[ -d "$postgres_init_path" ]]; then
  rm -rf "$postgres_init_path" 2>/dev/null || true
fi
if [[ ! -f "$postgres_init_path" ]]; then
  write_postgres_init_sql
fi
if [[ ! -f "$postgres_init_path" ]]; then
  echo -e "${CYAN}${BOLD}Error:${RESET} postgres/init.sql is missing and could not be created." >&2
  exit 1
fi
if ! head -n 5 "$postgres_init_path" | grep -Eq '^[[:space:]]*SET[[:space:]]+client_min_messages[[:space:]]+TO[[:space:]]+WARNING[[:space:]]*;[[:space:]]*$'; then
  tmp_init="${postgres_init_path}.tmp"
  {
    echo "SET client_min_messages TO WARNING;"
    echo
    cat "$postgres_init_path"
  } > "$tmp_init" && mv "$tmp_init" "$postgres_init_path"
fi
has_superset_in_nginx_conf=0
if [[ -f "$nginx_conf_path" ]] && grep -Eq '(^|[[:space:]])upstream[[:space:]]+superset([[:space:]]|\{)|proxy_pass[[:space:]]+https?://superset([:/[:space:]]|$)' "$nginx_conf_path"; then
  has_superset_in_nginx_conf=1
fi

is_repo_checkout=0
if [[ -f "${root_dir}/backend/Dockerfile" && -f "${root_dir}/frontend/Dockerfile" && -f "${root_dir}/init-secrets/Dockerfile" ]]; then
  is_repo_checkout=1
fi

select_yes_no_upgrade() {
  local prompt="${1:-Upgrade to the newer version?}"
  local default="${2:-no}"
  local options=("Yes" "No")
  local values=("yes" "no")
  local selected=1
  local key=""
  local escape_tail=""
  local option_count="${#options[@]}"

  if [[ "$default" == "yes" ]]; then
    selected=0
  fi

  if [[ ! -t 0 || ! -t 2 ]]; then
    local answer=""
    while true; do
      read -r -p "${prompt} [yes/no] (default: ${default}): " answer
      answer="$(printf "%s" "$answer" | tr '[:upper:]' '[:lower:]')"
      answer="$(printf "%s" "$answer" | tr -d ' \t\r\n')"
      if [[ -z "$answer" ]]; then
        printf "%s" "$default"
        return 0
      fi
      if [[ "$answer" == "y" || "$answer" == "yes" ]]; then
        printf "yes"
        return 0
      fi
      if [[ "$answer" == "n" || "$answer" == "no" ]]; then
        printf "no"
        return 0
      fi
      echo "Please enter 'yes' or 'no'." >&2
    done
  fi

  printf "\033[?25l" >&2
  trap 'printf "\033[?25h" >&2' RETURN

  printf "%s${DIM} (use arrow keys and Enter)${RESET}\n" "$prompt" >&2
  while true; do
    local idx
    for idx in "${!options[@]}"; do
      if (( idx == selected )); then
        printf "${GREEN}${BOLD}  > %s${RESET}\n" "${options[idx]}" >&2
      else
        printf "${DIM}    %s${RESET}\n" "${options[idx]}" >&2
      fi
    done

    IFS= read -r -s -n1 key
    if [[ "$key" == $'\x1b' ]]; then
      IFS= read -r -s -n2 escape_tail || true
      key+="$escape_tail"
      escape_tail=""
    fi

    case "$key" in
      $'\x1b[A'|$'\x1bOA')
        selected=$(( (selected + option_count - 1) % option_count ))
        ;;
      $'\x1b[B'|$'\x1bOB')
        selected=$(( (selected + 1) % option_count ))
        ;;
      ""|$'\n')
        printf "\033[%dA" "$option_count" >&2
        for idx in "${!options[@]}"; do
          printf "\r\033[K" >&2
          if (( idx < option_count - 1 )); then
            printf "\n" >&2
          fi
        done
        printf "\033[%dA" $(( option_count - 1 )) >&2
        printf "\r%s: %s\n" "$prompt" "${options[selected]}" >&2
        printf "%s" "${values[selected]}"
        return 0
        ;;
    esac

    printf "\033[%dA" "$option_count" >&2
  done
}

for arg in "$@"; do
  case "$arg" in
    --reconfigure)
      force_reconfigure=1
      ;;
    --upgrade|--ugrade)
      upgrade=1
      ;;
    --verbose)
      verbose=1
      ;;
    --quiet)
      quiet=1
      ;;
    *)
      compose_up_args+=("$arg")
      ;;
  esac
done

if (( upgrade == 1 && verbose == 0 )); then
  quiet=1
fi
if (( verbose == 1 )); then
  quiet=0
fi

latest_tag=""
latest_semver=""
if github_latest_tag; then
  latest_tag="$github_latest_tag_value"
  latest_semver="$(tag_semver "$latest_tag")"
  if [[ -z "$latest_semver" ]]; then
    latest_semver="$(normalize_version "$latest_tag")"
  fi
fi

current_semver="$(normalize_version "${SEKANT_DASHBOARD_VERSION:-}")"
update_available=0
if [[ -n "$latest_semver" && -n "$current_semver" ]] && semver_gt "$latest_semver" "$current_semver"; then
  update_available=1
fi

if (( update_available == 1 )); then
  if (( quiet == 0 )); then
    echo -e "${CYAN}${BOLD}Update available:${RESET} v${current_semver} -> v${latest_semver}"
  fi

  do_upgrade="no"
  if (( upgrade == 1 )); then
    do_upgrade="yes"
  else
    do_upgrade="$(select_yes_no_upgrade "Upgrade to v${latest_semver} now?" "no")"
  fi

  if [[ "$do_upgrade" == "yes" ]]; then
    if (( quiet == 0 )); then
      echo -e "${CYAN}${BOLD}Updating:${RESET} Downloading distribution files for ${latest_tag}..."
    fi
    if ! apply_update_from_github "$latest_tag"; then
      echo -e "${CYAN}${BOLD}Error:${RESET} Update failed." >&2
      exit 1
    fi

    new_args=()
    for arg in "$@"; do
      if [[ "$arg" == "--upgrade" || "$arg" == "--ugrade" ]]; then
        continue
      fi
      new_args+=("$arg")
    done
    new_args=(--upgrade "${new_args[@]+"${new_args[@]}"}")

    updated_script="${root_dir}/start.sh.new"
    if [[ -f "$updated_script" ]]; then
      chmod +x "$updated_script" >/dev/null 2>&1 || true
      if mv "$updated_script" "${root_dir}/start.sh" >/dev/null 2>&1; then
        chmod +x "${root_dir}/start.sh" >/dev/null 2>&1 || true
        SEKANT_FORCE_IMAGE_TAG="${latest_semver}" exec "${root_dir}/start.sh" "${new_args[@]+"${new_args[@]}"}"
      fi
      SEKANT_FORCE_IMAGE_TAG="${latest_semver}" exec "$updated_script" "${new_args[@]+"${new_args[@]}"}"
    fi
    SEKANT_FORCE_IMAGE_TAG="${latest_semver}" exec "${root_dir}/start.sh" "${new_args[@]+"${new_args[@]}"}"
  fi
else
  if (( upgrade == 1 && quiet == 0 )); then
    echo -e "${CYAN}${BOLD}No update available:${RESET} continuing with current version v${current_semver}"
  fi
fi

if (( quiet == 1 )); then
  upgrade_log_file="$(mktemp)"
fi

run_cmd() {
  if (( quiet == 1 )); then
    "$@" >>"$upgrade_log_file" 2>&1
    return $?
  fi
  "$@"
}

compose_override_file=""
compose_file_args=("-f" "${root_dir}/docker-compose.yml")

run_compose() {
  run_cmd "${compose_cmd[@]}" "${compose_file_args[@]}" "$@"
}

load_distribution_images() {
  if [[ ! -f "${root_dir}/load-images.sh" ]]; then
    return 0
  fi
  if [[ ! -d "${root_dir}/images" ]]; then
    return 0
  fi

  if (( quiet == 1 )); then
    echo -e "${CYAN}${BOLD}Fixing${RESET}" >&2
  else
    echo "Loading Docker images..." >&2
  fi

  run_cmd bash "${root_dir}/load-images.sh"
}

ensure_docker_config_no_desktop_helper() {
  local docker_config_dir="${DOCKER_CONFIG:-${HOME}/.docker}"
  local config_path="${docker_config_dir}/config.json"

  if [[ -f "${config_path}" ]] && grep -Eq '"credsStore"[[:space:]]*:|"credHelpers"[[:space:]]*:' "${config_path}"; then
    if grep -Eqi '"credsStore"[[:space:]]*:[[:space:]]*"desktop(\.exe)?"|"docker-credential-desktop(\.exe)?"' "${config_path}"; then
      if command -v uname >/dev/null 2>&1; then
        if [[ "$(uname -s 2>/dev/null || true)" != "Linux" ]]; then
          return 0
        fi
      fi
      mkdir -p "${root_dir}/.docker-no-credential-helper"
      export DOCKER_CONFIG="${root_dir}/.docker-no-credential-helper"
      cat > "${DOCKER_CONFIG}/config.json" <<'EOF'
{
  "auths": {}
}
EOF
      chmod 700 "${DOCKER_CONFIG}" 2>/dev/null || true
      chmod 600 "${DOCKER_CONFIG}/config.json" 2>/dev/null || true
      if (( quiet == 0 )); then
        echo -e "${CYAN}${BOLD}Info:${RESET} Detected Docker Desktop credential helper config (credsStore/credHelpers=desktop[.exe])." >&2
        echo "Using an isolated Docker config to avoid docker-credential-desktop.exe exec format errors in Linux shells." >&2
      fi
      return 0
    fi
  fi
}

ensure_docker_config_no_desktop_helper || true

if (( upgrade == 1 )); then
  load_distribution_images || true
else
  image_loaded_marker="${root_dir}/.images_loaded"
  if [[ -n "${SEKANT_DASHBOARD_VERSION:-}" ]]; then
    image_loaded_marker="${root_dir}/.images_loaded_${SEKANT_DASHBOARD_VERSION}"
  fi
  if [[ -f "${root_dir}/load-images.sh" && -d "${root_dir}/images" && ! -f "$image_loaded_marker" ]]; then
    load_distribution_images || true
    run_cmd touch "$image_loaded_marker" 2>/dev/null || true
  fi
fi

compose_service_has_build() {
  local service="$1"
  awk -v svc="$service" '
    $0 ~ ("^  " svc ":$") { in_service=1; next }
    in_service && $0 ~ "^    build:" { found=1; exit }
    in_service && $0 ~ "^  [a-z0-9-]+:$" { exit }
    END { exit(found ? 0 : 1) }
  ' "${root_dir}/docker-compose.yml"
}

ensure_image_available() {
  local image="$1"
  if docker image inspect "$image" >/dev/null 2>&1; then
    return 0
  fi

  if [[ -f "${root_dir}/load-images.sh" ]]; then
    if (( quiet == 1 )); then
      echo -e "${CYAN}${BOLD}Fixing${RESET}" >&2
    else
      echo "Loading Docker images..." >&2
    fi
    set +e
    run_cmd bash "${root_dir}/load-images.sh"
    set -e
  fi

  if [[ "${SKIP_DOCKER_PULL:-0}" != "1" ]]; then
    set +e
    run_cmd docker pull "$image"
    set -e
  fi

  docker image inspect "$image" >/dev/null 2>&1
}

container_status() {
  local container_name="$1"
  docker inspect -f '{{.State.Status}}' "$container_name" 2>/dev/null || true
}

container_health_status() {
  local container_name="$1"
  docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$container_name" 2>/dev/null || true
}

wait_for_container_ready() {
  local container_name="$1"
  local timeout_seconds="$2"
  local start_seconds="$SECONDS"
  while true; do
    local health
    health="$(container_health_status "$container_name")"
    if [[ "$health" == "healthy" || "$health" == "running" ]]; then
      return 0
    fi
    if [[ "$health" == "exited" || "$health" == "dead" ]]; then
      return 1
    fi
    if (( SECONDS - start_seconds > timeout_seconds )); then
      return 1
    fi
    sleep 2
  done
}

ensure_postgres_bootstrap() {
  local container_name="sekant-postgres"
  local pg_user
  pg_user="$(trim_whitespace "$(read_env_value "POSTGRES_USER")")"
  pg_user="${pg_user:-sekant}"

  if ! docker container inspect "$container_name" >/dev/null 2>&1; then
    return 1
  fi

  local init_file="/docker-entrypoint-initdb.d/init.sql"
  if ! docker exec "$container_name" sh -c "test -f \"$init_file\" && ! test -d \"$init_file\""; then
    return 1
  fi

  set +e
  docker exec -i "$container_name" psql -U "$pg_user" -d postgres -tc "SELECT 1 FROM pg_database WHERE datname='sekant';" | tr -d '\r' | grep -q "1"
  has_sekant_db=$?
  set -e
  if (( has_sekant_db != 0 )); then
    docker exec -i "$container_name" psql -U "$pg_user" -d postgres -c "CREATE DATABASE sekant;" >/dev/null
  fi

  docker exec -i "$container_name" psql -U "$pg_user" -d sekant -f "$init_file" >/dev/null
  return 0
}

wait_for_sekant_ready() {
  local items=(
    "sekant-init-secrets:120"
    "sekant-postgres:240"
    "sekant-clickhouse:240"
    "sekant-redis:120"
    "sekant-sql-validator:240"
    "sekant-keycloak:600"
    "sekant-backend:300"
    "sekant-frontend:300"
    "sekant-nginx:240"
    "sekant-caddy:300"
    "sekant-fluent-bit:240"
  )

  local item
  for item in "${items[@]}"; do
    local container_name="${item%%:*}"
    local timeout_seconds="${item##*:}"
    local status
    status="$(container_status "$container_name")"
    if [[ -z "$status" ]]; then
      return 1
    fi
    if ! wait_for_container_ready "$container_name" "$timeout_seconds"; then
      return 1
    fi
    if [[ "$container_name" == "sekant-postgres" ]]; then
      if ! ensure_postgres_bootstrap; then
        return 1
      fi
    fi
  done
  return 0
}

clickhouse_exec_sql() {
  local sql="$1"
  local ch_user ch_password
  ch_user="$(trim_whitespace "$(read_env_value "CH_APP_ADMIN_USER")")"
  ch_user="${ch_user:-ch_app_admin}"
  ch_password="$(read_volume_file "$secrets_volume_name" "ch_app_admin_password" | tr -d '\r\n')"
  if [[ -z "$ch_password" ]]; then
    echo -e "${CYAN}${BOLD}Error:${RESET} Could not read ClickHouse admin password from secrets volume." >&2
    return 1
  fi
  docker exec -i "sekant-clickhouse" clickhouse-client --user "$ch_user" --password "$ch_password" -q "$sql"
}

ensure_clickhouse_retention_ttl() {
  local retention_days
  retention_days="$(trim_whitespace "$(read_env_value "CLICKHOUSE_RETENTION_DAYS")")"
  if [[ -z "$retention_days" ]]; then
    return 0
  fi
  if ! is_valid_retention_days "$retention_days"; then
    echo -e "${CYAN}${BOLD}Error:${RESET} CLICKHOUSE_RETENTION_DAYS must be a whole number >= 7." >&2
    echo "Current CLICKHOUSE_RETENTION_DAYS=${retention_days}" >&2
    return 1
  fi

  if ! docker container inspect "sekant-clickhouse" >/dev/null 2>&1; then
    echo -e "${CYAN}${BOLD}Error:${RESET} ClickHouse container not found; cannot apply retention TTL." >&2
    return 1
  fi

  clickhouse_exec_sql "SYSTEM START TTL MERGES" >/dev/null 2>&1 || true

  local has_security_events
  has_security_events="$(clickhouse_exec_sql "SELECT count() FROM system.tables WHERE database='sekant' AND name='security_events'" | tr -d '\r' | head -n 1 | tr -d '[:space:]' || true)"
  if [[ "$has_security_events" == "1" ]]; then
    clickhouse_exec_sql "ALTER TABLE sekant.security_events MODIFY TTL toDateTime(event_utc_ms, 'UTC') + INTERVAL ${retention_days} DAY DELETE" >/dev/null
    clickhouse_exec_sql "ALTER TABLE sekant.security_events MATERIALIZE TTL" >/dev/null 2>&1 || true
  fi

  local has_rules_hit
  has_rules_hit="$(clickhouse_exec_sql "SELECT count() FROM system.tables WHERE database='sekant' AND name='rules_hit'" | tr -d '\r' | head -n 1 | tr -d '[:space:]' || true)"
  if [[ "$has_rules_hit" == "1" ]]; then
    clickhouse_exec_sql "ALTER TABLE sekant.rules_hit MODIFY TTL toDateTime(hit_timestamp, 'UTC') + INTERVAL ${retention_days} DAY DELETE" >/dev/null 2>&1 || true
    clickhouse_exec_sql "ALTER TABLE sekant.rules_hit MATERIALIZE TTL" >/dev/null 2>&1 || true
  fi

  return 0
}

# Ensure all scripts have execute permissions, skipping large directories
find "${root_dir}" \( -name node_modules -o -name .git -o -name .next \) -prune -o -name "*.sh" -exec chmod +x {} +

trim_whitespace() {
  local raw_text="$1"
  raw_text="${raw_text#"${raw_text%%[![:space:]]*}"}"
  raw_text="${raw_text%"${raw_text##*[![:space:]]}"}"
  printf "%s" "$raw_text"
}

sanitize_compose_project_name() {
  local raw_name="$1"
  local name=""
  name="$(trim_whitespace "$raw_name" | tr '[:upper:]' '[:lower:]')"
  name="$(printf "%s" "$name" | sed -E 's/[^a-z0-9_-]+/-/g; s/^-+//; s/-+$//; s/^_+//; s/_+$//')"
  if [[ -z "$name" ]]; then
    name="sekant"
  fi
  if [[ ! "$name" =~ ^[a-z0-9] ]]; then
    name="s${name}"
  fi
  printf "%s" "$name"
}

normalize_hostname() {
  local raw_hostname="$1"
  raw_hostname="$(trim_whitespace "$raw_hostname")"
  raw_hostname="${raw_hostname#\`}"
  raw_hostname="${raw_hostname%\`}"
  raw_hostname="${raw_hostname#\"}"
  raw_hostname="${raw_hostname%\"}"
  raw_hostname="${raw_hostname#\'}"
  raw_hostname="${raw_hostname%\'}"
  raw_hostname="${raw_hostname#http://}"
  raw_hostname="${raw_hostname#https://}"
  raw_hostname="${raw_hostname%%/*}"
  raw_hostname="${raw_hostname%%\?*}"
  raw_hostname="${raw_hostname%%,*}"
  raw_hostname="$(trim_whitespace "$raw_hostname")"
  raw_hostname="${raw_hostname%,}"
  raw_hostname="$(printf "%s" "$raw_hostname" | sed -E 's/:[0-9]+$//')"
  printf "%s" "$raw_hostname"
}

write_env_value() {
  local key="$1"
  local value="$2"
  local temp_file
  temp_file="$(mktemp)"
  if [[ -f "$env_file" ]]; then
    awk -F= -v k="$key" -v v="$value" '
      BEGIN { updated=0 }
      $1==k { print k "=" v; updated=1; next }
      { print }
      END { if (!updated) print k "=" v }
    ' "$env_file" > "$temp_file"
  else
    printf '%s=%s\n' "$key" "$value" > "$temp_file"
  fi
  mv "$temp_file" "$env_file"
}

read_env_value() {
  local key="$1"
  local source_line=""
  if [[ -f "$env_file" ]]; then
    source_line="$(awk -F= -v k="$key" '$1==k { sub(/^[^=]*=/, "", $0); print $0; exit }' "$env_file")"
  fi
  printf "%s" "${source_line}"
}

ensure_image_config() {
  local repo_default="sekantsec/management-console"
  local tag_default="latest"
  if [[ -n "${SEKANT_DASHBOARD_VERSION:-}" ]]; then
    tag_default="${SEKANT_DASHBOARD_VERSION}"
  fi

  if [[ -n "${SEKANT_FORCE_IMAGE_TAG:-}" ]]; then
    write_env_value "SEKANT_IMAGE_TAG" "${SEKANT_FORCE_IMAGE_TAG}"
  fi

  local repo_current
  repo_current="$(trim_whitespace "$(read_env_value "SEKANT_IMAGE_REPO")")"
  if [[ -z "$repo_current" ]]; then
    write_env_value "SEKANT_IMAGE_REPO" "$repo_default"
  fi

  local tag_current
  tag_current="$(trim_whitespace "$(read_env_value "SEKANT_IMAGE_TAG")")"
  if [[ -z "$tag_current" ]]; then
    write_env_value "SEKANT_IMAGE_TAG" "$tag_default"
  fi
}

ensure_image_config

compare_semver() {
  local a="$1"
  local b="$2"

  IFS='.' read -r a1 a2 a3 <<<"${a:-0.0.0}"
  IFS='.' read -r b1 b2 b3 <<<"${b:-0.0.0}"

  a1="${a1:-0}"; a2="${a2:-0}"; a3="${a3:-0}"
  b1="${b1:-0}"; b2="${b2:-0}"; b3="${b3:-0}"

  if (( a1 > b1 )); then printf "1"; return 0; fi
  if (( a1 < b1 )); then printf "-1"; return 0; fi
  if (( a2 > b2 )); then printf "1"; return 0; fi
  if (( a2 < b2 )); then printf "-1"; return 0; fi
  if (( a3 > b3 )); then printf "1"; return 0; fi
  if (( a3 < b3 )); then printf "-1"; return 0; fi
  printf "0"
}

fetch_url() {
  local url="$1"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$url"
    return $?
  fi
  if command -v wget >/dev/null 2>&1; then
    wget -qO- "$url"
    return $?
  fi
  return 127
}

check_for_upgrade_notice() {
  local dashboard_version="${SEKANT_DASHBOARD_VERSION:-}"
  if [[ -z "$dashboard_version" ]]; then
    return 0
  fi

  local repo_full
  repo_full="$(trim_whitespace "$(read_env_value "SEKANT_IMAGE_REPO")")"
  if [[ -z "$repo_full" || "$repo_full" != */* ]]; then
    return 0
  fi

  local namespace="${repo_full%%/*}"
  local repo_name="${repo_full#*/}"
  local api_url="https://hub.docker.com/v2/repositories/${namespace}/${repo_name}/tags?page_size=100"

  local max_version=""
  local page_url="$api_url"
  local pages_left=3

  while [[ -n "$page_url" && $pages_left -gt 0 ]]; do
    local body
    body="$(fetch_url "$page_url" 2>/dev/null || true)"
    if [[ -z "$body" ]]; then
      break
    fi

    while IFS= read -r tag_name; do
      [[ -z "$tag_name" ]] && continue
      if [[ ! "${tag_name}" =~ ^backend- ]]; then
        continue
      fi
      local version_candidate="${tag_name#backend-}"
      if [[ "${version_candidate}" =~ ^[0-9]+-[0-9]+-[0-9]+$ ]]; then
        version_candidate="${version_candidate//-/.}"
      fi
      if [[ ! "${version_candidate}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        continue
      fi
      if [[ -z "$max_version" ]]; then
        max_version="$version_candidate"
      else
        local cmp
        cmp="$(compare_semver "$version_candidate" "$max_version")"
        if [[ "$cmp" == "1" ]]; then
          max_version="$version_candidate"
        fi
      fi
    done < <(printf "%s" "$body" | sed -nE 's/.*"name":"(backend-[0-9]+[.-][0-9]+[.-][0-9]+)".*/\1/p')

    local next_url
    next_url="$(printf "%s" "$body" | sed -nE 's/.*"next":"([^"]+)".*/\1/p' | head -n 1)"
    page_url="$next_url"
    pages_left=$(( pages_left - 1 ))
  done

  if [[ -z "$max_version" ]]; then
    return 0
  fi

  local cmp
  cmp="$(compare_semver "$max_version" "$dashboard_version")"
  if [[ "$cmp" == "1" ]]; then
    echo -e "${CYAN}${BOLD}VERSION UPGRADE AVAILABLE:${RESET} CONTACT SEKANT SECURITY (Installed: ${dashboard_version}, Latest: ${max_version})"
  fi
}

check_for_upgrade_notice || true

detect_existing_compose_project() {
  local suffix_secrets="_sekant_secrets"
  local prefix=""
  local matches=()

  while IFS= read -r volume_name; do
    [[ -z "$volume_name" ]] && continue
    case "$volume_name" in
      *"${suffix_secrets}")
        prefix="${volume_name%$suffix_secrets}"
        matches+=("$prefix")
        ;;
    esac
  done < <(docker volume ls --format '{{.Name}}')

  if (( ${#matches[@]} == 1 )); then
    printf "%s" "${matches[0]}"
    return 0
  fi

  if (( ${#matches[@]} > 1 )); then
    echo "Multiple existing Sekant volume sets detected: ${matches[*]}" >&2
    echo "Set COMPOSE_PROJECT_NAME in .env to choose one explicitly." >&2
    return 2
  fi

  return 1
}

detect_running_compose_project() {
  local container_name="sekant-caddy"
  local project=""
  if docker container inspect "$container_name" >/dev/null 2>&1; then
    project="$(docker inspect -f '{{ index .Config.Labels "com.docker.compose.project" }}' "$container_name" 2>/dev/null || true)"
    project="$(trim_whitespace "$project")"
    if [[ -n "$project" && "$project" != "<no value>" ]]; then
      printf "%s" "$project"
      return 0
    fi
  fi
  return 1
}

has_running_sekant_deployment() {
  docker container inspect "sekant-caddy" >/dev/null 2>&1 && return 0
  docker container inspect "sekant-nginx" >/dev/null 2>&1 && return 0
  return 1
}

remove_container_if_exists() {
  local container_name="$1"
  if docker container inspect "$container_name" >/dev/null 2>&1; then
    docker rm -f "$container_name" >/dev/null 2>&1 || true
  fi
}

resolve_compose_command() {
  compose_cmd=()
  if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    compose_cmd=(docker compose)
  elif command -v docker-compose >/dev/null 2>&1; then
    compose_cmd=(docker-compose)
  else
    echo "docker compose (or docker-compose) not found in PATH." >&2
    exit 1
  fi
}

prompt_non_empty() {
  local label="$1"
  local value=""
  while [[ -z "$value" ]]; do
    read -r -p "${label}: " value
    value="$(trim_whitespace "$value")"
  done
  printf "%s" "$value"
}

prompt_with_default() {
  local label="$1"
  local default_value="$2"
  local value=""
  read -r -p "${label} [default: ${default_value}]: " value
  value="$(trim_whitespace "$value")"
  if [[ -z "$value" ]]; then
    printf "%s" "$default_value"
  else
    printf "%s" "$value"
  fi
}

prompt_with_default_text() {
  local prompt_text="$1"
  local default_value="$2"
  local value=""
  read -r -p "${prompt_text}" value
  value="$(trim_whitespace "$value")"
  if [[ -z "$value" ]]; then
    printf "%s" "$default_value"
  else
    printf "%s" "$value"
  fi
}

prompt_secret_with_default_text() {
  local prompt_text="$1"
  local default_value="$2"
  local value=""
  read -r -s -p "${prompt_text}" value
  printf "\n" >&2
  value="$(trim_whitespace "$value")"
  if [[ -z "$value" ]]; then
    printf "%s" "$default_value"
  else
    printf "%s" "$value"
  fi
}

prompt_secret() {
  local label="$1"
  local value=""
  while [[ -z "$value" ]]; do
    read -r -s -p "${label}: " value
    printf "\n" >&2
    value="$(trim_whitespace "$value")"
  done
  printf "%s" "$value"
}

prompt_secret_with_default() {
  local label="$1"
  local default_value="$2"
  local value=""
  read -r -s -p "${label} [default: ${default_value}]: " value
  printf "\n" >&2
  value="$(trim_whitespace "$value")"
  if [[ -z "$value" ]]; then
    printf "%s" "$default_value"
  else
    printf "%s" "$value"
  fi
}

is_valid_email() {
  local value="$1"
  [[ "$value" =~ ^[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$ ]]
}

prompt_email_required() {
  local label="$1"
  local value=""
  while true; do
    read -r -p "${label}" value
    value="$(trim_whitespace "$value")"
    if is_valid_email "$value"; then
      printf "%s" "$value"
      return 0
    fi
    echo "Please enter a valid email address." >&2
  done
}

is_valid_port() {
  local value="$1"
  [[ "$value" =~ ^[0-9]+$ ]] || return 1
  (( value >= 1 && value <= 65535 ))
}

is_valid_positive_int() {
  local value="$1"
  [[ "$value" =~ ^[0-9]+$ ]] || return 1
  (( value >= 1 ))
}

is_valid_retention_days() {
  local value="$1"
  [[ "$value" =~ ^[0-9]+$ ]] || return 1
  (( value >= 7 ))
}

prompt_port_with_default() {
  local label="$1"
  local default_value="$2"
  local value=""
  while true; do
    value="$(prompt_with_default "$label" "$default_value")"
    if is_valid_port "$value"; then
      printf "%s" "$value"
      return 0
    fi
    echo "Please enter a valid TCP port (1-65535)." >&2
  done
}

prompt_port_with_default_text() {
  local prompt_text="$1"
  local default_value="$2"
  local value=""
  while true; do
    value="$(prompt_with_default_text "$prompt_text" "$default_value")"
    if is_valid_port "$value"; then
      printf "%s" "$value"
      return 0
    fi
    echo "Please enter a valid TCP port (1-65535)." >&2
  done
}

prompt_positive_int_with_default_text() {
  local prompt_text="$1"
  local default_value="$2"
  local value=""
  while true; do
    value="$(prompt_with_default_text "$prompt_text" "$default_value")"
    if is_valid_positive_int "$value"; then
      printf "%s" "$value"
      return 0
    fi
    echo "Please enter a whole number >= 1." >&2
  done
}

prompt_retention_days_with_default_text() {
  local prompt_text="$1"
  local default_value="$2"
  local value=""
  while true; do
    value="$(prompt_with_default_text "$prompt_text" "$default_value")"
    if is_valid_retention_days "$value"; then
      printf "%s" "$value"
      return 0
    fi
    echo "Please enter a whole number >= 7." >&2
  done
}

is_port_in_use() {
  local port="$1"
  if command -v timeout >/dev/null 2>&1; then
    timeout 1 bash -c "echo >/dev/tcp/127.0.0.1/${port}" >/dev/null 2>&1
  else
    bash -c "echo >/dev/tcp/127.0.0.1/${port}" >/dev/null 2>&1
  fi
}

assert_port_free() {
  local port="$1"
  local label="$2"
  if is_port_in_use "$port"; then
    echo -e "${CYAN}${BOLD}Error:${RESET} ${label} port ${port} is already in use on 127.0.0.1." >&2
    exit 1
  fi
}

render_menu_option() {
  local option_label="$1"
  local is_selected="$2"
  if [[ "$is_selected" == "1" ]]; then
    printf "${GREEN}${BOLD}  > %s${RESET}\n" "$option_label" >&2
  else
    printf "${DIM}    %s${RESET}\n" "$option_label" >&2
  fi
}

select_clickhouse_mode() {
  local options=("Local" "Remote")
  local values=("local" "remote")
  local selected=0
  local key=""
  local escape_tail=""
  local option_count="${#options[@]}"

  if [[ ! -t 0 || ! -t 2 ]]; then
    local answer=""
    while true; do
      read -r -p "Database setup [local/remote] (default: local): " answer
      answer="$(printf "%s" "$answer" | tr '[:upper:]' '[:lower:]')"
      answer="$(trim_whitespace "$answer")"
      if [[ -z "$answer" || "$answer" == "local" || "$answer" == "remote" ]]; then
        printf "%s" "${answer:-local}"
        return 0
      fi
      echo "Please enter 'local' or 'remote'." >&2
    done
  fi

  printf "\033[?25l" >&2
  trap 'printf "\033[?25h" >&2' RETURN

  printf "Select Database setup${DIM} (use arrow keys and Enter)${RESET}\n" >&2
  while true; do
    local idx
    for idx in "${!options[@]}"; do
      if (( idx == selected )); then
        render_menu_option "${options[idx]}" "1"
      else
        render_menu_option "${options[idx]}" "0"
      fi
    done

    IFS= read -r -s -n1 key
    if [[ "$key" == $'\x1b' ]]; then
      IFS= read -r -s -n2 escape_tail || true
      key+="$escape_tail"
      escape_tail=""
    fi

    case "$key" in
      $'\x1b[A'|$'\x1bOA')
        selected=$(( (selected + option_count - 1) % option_count ))
        ;;
      $'\x1b[B'|$'\x1bOB')
        selected=$(( (selected + 1) % option_count ))
        ;;
      ""|$'\n')
        printf "\033[%dA" "$option_count" >&2
        for idx in "${!options[@]}"; do
          printf "\r\033[K" >&2
          if (( idx < option_count - 1 )); then
            printf "\n" >&2
          fi
        done
        printf "\033[%dA" $(( option_count - 1 )) >&2
        printf "\rDatabase setup: %s\n" "${options[selected]}" >&2
        printf "%s" "${values[selected]}"
        return 0
        ;;
    esac

    printf "\033[%dA" "$option_count" >&2
  done
}

configure_local_clickhouse() {
  mkdir -p "$storage_dir"
  cp "${root_dir}/clickhouse/storage.local.xml" "${storage_dir}/storage.xml"
  write_env_value "CLICKHOUSE_SETUP_MODE" "local"
  write_env_value "CLICKHOUSE_STORAGE_POLICY" ""
  write_env_value "CLICKHOUSE_S3_ENDPOINT" ""
  write_env_value "CLICKHOUSE_S3_ACCESS_KEY_ID" ""
  write_env_value "CLICKHOUSE_S3_SECRET_ACCESS_KEY" ""
  write_env_value "CLICKHOUSE_S3_REGION" ""
}

configure_remote_clickhouse() {
  local endpoint_base bucket prefix region access_key secret_key

  endpoint_base="$(prompt_non_empty "S3 endpoint base (example: https://s3.amazonaws.com)")"
  bucket="$(prompt_non_empty "S3 bucket")"
  read -r -p "S3 path prefix (optional): " prefix
  prefix="$(trim_whitespace "$prefix")"
  read -r -p "S3 region (optional): " region
  region="$(trim_whitespace "$region")"
  access_key="$(prompt_non_empty "S3 access key id")"
  secret_key="$(prompt_secret "S3 secret access key")"

  endpoint_base="${endpoint_base%/}"
  bucket="${bucket#/}"
  bucket="${bucket%/}"
  prefix="${prefix#/}"
  prefix="${prefix%/}"

  local s3_endpoint="${endpoint_base}/${bucket}"
  if [[ -n "$prefix" ]]; then
    s3_endpoint="${s3_endpoint}/${prefix}"
  fi
  s3_endpoint="${s3_endpoint%/}/"

  mkdir -p "$storage_dir"
  cp "${root_dir}/clickhouse/storage.remote.xml" "${storage_dir}/storage.xml"
  write_env_value "CLICKHOUSE_SETUP_MODE" "remote"
  write_env_value "CLICKHOUSE_STORAGE_POLICY" "s3"
  write_env_value "CLICKHOUSE_S3_ENDPOINT" "$s3_endpoint"
  write_env_value "CLICKHOUSE_S3_ACCESS_KEY_ID" "$access_key"
  write_env_value "CLICKHOUSE_S3_SECRET_ACCESS_KEY" "$secret_key"
  write_env_value "CLICKHOUSE_S3_REGION" "$region"
}

configure_remote_clickhouse_from_env() {
  local endpoint bucket_key secret_key region
  endpoint="$(read_env_value "CLICKHOUSE_S3_ENDPOINT")"
  bucket_key="$(read_env_value "CLICKHOUSE_S3_ACCESS_KEY_ID")"
  secret_key="$(read_env_value "CLICKHOUSE_S3_SECRET_ACCESS_KEY")"
  region="$(read_env_value "CLICKHOUSE_S3_REGION")"

  if [[ -z "$endpoint" || -z "$bucket_key" || -z "$secret_key" ]]; then
    echo -e "${CYAN}${BOLD}Remote Database mode is configured but required S3 values are missing.${RESET}" >&2
    echo "Run with --reconfigure to enter remote storage values again." >&2
    exit 1
  fi

  mkdir -p "$storage_dir"
  cp "${root_dir}/clickhouse/storage.remote.xml" "${storage_dir}/storage.xml"
  write_env_value "CLICKHOUSE_SETUP_MODE" "remote"
  write_env_value "CLICKHOUSE_STORAGE_POLICY" "s3"
  write_env_value "CLICKHOUSE_S3_ENDPOINT" "$endpoint"
  write_env_value "CLICKHOUSE_S3_ACCESS_KEY_ID" "$bucket_key"
  write_env_value "CLICKHOUSE_S3_SECRET_ACCESS_KEY" "$secret_key"
  write_env_value "CLICKHOUSE_S3_REGION" "$region"
}

resolve_compose_command

# Validate that docker is running
if ! docker info >/dev/null 2>&1; then
  echo -e "${CYAN}${BOLD}Error: Docker is not running. Please start Docker first.${RESET}" >&2
  exit 1
fi

# Per-service platform pinning (below) handles per-image arch. Clear any inherited
# global override so multi-arch images can resolve to the host arch naturally.
unset DOCKER_DEFAULT_PLATFORM

host_os="$(uname -s 2>/dev/null || true)"
host_arch_raw="$(uname -m 2>/dev/null || true)"
case "$host_arch_raw" in
  x86_64|amd64)   host_arch="amd64" ;;
  arm64|aarch64)  host_arch="arm64" ;;
  *)              host_arch="" ;;
esac
host_platform="linux/${host_arch}"

platform_dir="$host_arch"
has_native_distribution_images=0
if [[ -n "$platform_dir" && -d "${root_dir}/images/${platform_dir}" ]]; then
  if find "${root_dir}/images/${platform_dir}" -maxdepth 1 -name "*.tar" -type f 2>/dev/null | head -n 1 | grep -q .; then
    has_native_distribution_images=1
  fi
fi

# Per-image platform detection: probe each service's image for native-arch
# support and pin platform: linux/amd64 only on services that lack a native
# variant. Multi-arch images (redis, postgres, keycloak, ...) run native on the
# host; amd64-only images (sekant custom builds) run via emulation. Generated
# into a compose override; no global DOCKER_DEFAULT_PLATFORM is set.
image_decision() {
  # Print one of: pin | native | unknown
  #   pin     -> image has no ${host_arch} variant; pin platform: linux/amd64
  #   native  -> image has a ${host_arch} variant; ensure cache matches, no pin
  #   unknown -> manifest unreachable + no local cache; no pin, let daemon try
  local image="$1"
  [[ -z "$host_arch" ]] && { echo unknown; return; }
  local manifest
  manifest="$(docker manifest inspect "$image" 2>/dev/null || true)"
  if [[ -n "$manifest" ]]; then
    if grep -Eq "\"architecture\"[[:space:]]*:[[:space:]]*\"${host_arch}\"" <<<"$manifest"; then
      echo native; return
    fi
    echo pin; return
  fi
  local local_arch
  local_arch="$(docker image inspect "$image" --format '{{.Architecture}}' 2>/dev/null || true)"
  if [[ -n "$local_arch" ]]; then
    [[ "$local_arch" == "$host_arch" ]] && { echo native; return; }
    echo pin; return
  fi
  echo unknown
}

# Note: we don't reliably detect *which* platform's layers are present in the
# local cache (the legacy `Architecture` field is empty for OCI image indexes,
# and `.Manifests` isn't populated for cached images). So instead of "detect
# then pull", we just `docker pull --platform=<host>` every native image. Pull
# is idempotent: no-op when layers already exist, downloads only what's missing.

generate_platform_override() {
  [[ -z "$host_arch" ]] && return 0
  command -v python3 >/dev/null 2>&1 || return 0

  local compose_json
  compose_json="$("${compose_cmd[@]}" -f "${root_dir}/docker-compose.yml" config --format json 2>/dev/null || true)"
  [[ -z "$compose_json" ]] && return 0

  local pairs
  pairs="$(printf '%s' "$compose_json" | python3 -c '
import sys, json
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for name, svc in (data.get("services") or {}).items():
    img = (svc or {}).get("image")
    if img:
        print(f"{name}\t{img}")
' 2>/dev/null || true)"
  [[ -z "$pairs" ]] && return 0

  local override_path="${root_dir}/.docker-compose.platform.yml"
  local -a pinned=() native_pulls=()
  local svc img decision
  while IFS=$'\t' read -r svc img; do
    [[ -z "$svc" || -z "$img" ]] && continue
    decision="$(image_decision "$img")"
    case "$decision" in
      pin)    pinned+=("$svc") ;;
      native) native_pulls+=("$img") ;;
    esac
  done <<<"$pairs"

  # De-duplicate native_pulls (multiple services can share an image).
  # Bash 3.2 (stock on macOS) lacks associative arrays, so use a sentinel string.
  if (( ${#native_pulls[@]} > 0 )); then
    local seen=$'\n'
    local -a uniq=()
    for img in "${native_pulls[@]}"; do
      if [[ "$seen" != *$'\n'"$img"$'\n'* ]]; then
        seen="${seen}${img}"$'\n'
        uniq+=("$img")
      fi
    done
    if (( quiet == 0 )); then
      echo -e "${CYAN}${BOLD}Platform:${RESET} ensuring ${host_platform} layers cached for ${#uniq[@]} multi-arch image(s)..."
    fi
    for img in "${uniq[@]}"; do
      run_cmd docker pull --platform="${host_platform}" "$img" || true
    done
  fi

  if (( ${#pinned[@]} == 0 )); then
    rm -f "$override_path"
    if (( quiet == 0 )); then
      echo -e "${CYAN}${BOLD}Platform:${RESET} all images support ${host_platform} natively."
    fi
    return 0
  fi

  {
    echo "# Auto-generated by start.sh — do not edit. Pins amd64 only for services"
    echo "# whose image has no native ${host_arch} variant; everything else runs native."
    echo "services:"
    for svc in "${pinned[@]}"; do
      printf '  %s:\n    platform: linux/amd64\n' "$svc"
    done
  } >"$override_path"
  compose_file_args+=("-f" "$override_path")

  if (( quiet == 0 )); then
    echo -e "${CYAN}${BOLD}Platform:${RESET} host is ${host_platform}. Pinning linux/amd64 for ${#pinned[@]} service(s) lacking a native ${host_arch} image: ${pinned[*]}"
    if [[ "$host_arch" == "arm64" && "$host_os" == "Darwin" ]]; then
      echo "Those services run via emulation — ensure Docker Desktop has 'Use Rosetta for x86/amd64 emulation' enabled." >&2
    fi
  fi
}

generate_platform_override

existing_compose_project="$(trim_whitespace "$(read_env_value "COMPOSE_PROJECT_NAME")")"
if [[ -z "$existing_compose_project" ]]; then
  existing_compose_project="$(detect_running_compose_project 2>/dev/null || true)"
fi
if [[ -z "$existing_compose_project" ]]; then
  existing_compose_project="$(detect_existing_compose_project 2>/dev/null || true)"
fi
existing_compose_project="${existing_compose_project:-sekant}"

compose_project_current="$(trim_whitespace "$(read_env_value "COMPOSE_PROJECT_NAME")")"
if [[ -z "$compose_project_current" ]]; then
  write_env_value "COMPOSE_PROJECT_NAME" "$existing_compose_project"
fi

secrets_volume_name="${existing_compose_project}_sekant_secrets"
clickhouse_volume_name="${existing_compose_project}_clickhouse_data"
postgres_volume_name="${existing_compose_project}_postgres_data"
has_existing_volumes=0
has_secrets_volume=0
has_database_volume=0
has_postgres_volume=0
if docker volume inspect "$secrets_volume_name" >/dev/null 2>&1; then
  has_secrets_volume=1
fi
if docker volume inspect "$clickhouse_volume_name" >/dev/null 2>&1; then
  has_database_volume=1
fi
if docker volume inspect "$postgres_volume_name" >/dev/null 2>&1; then
  has_postgres_volume=1
fi
if (( has_secrets_volume == 1 || has_database_volume == 1 || has_postgres_volume == 1 )); then
  has_existing_volumes=1
  echo -e "${CYAN}${BOLD}Detected existing deployment volumes; reusing persisted secrets and database data.${RESET}"
fi

resolve_helper_image() {
  local image_repo=""
  local image_tag=""
  image_repo="$(trim_whitespace "$(read_env_value "SEKANT_IMAGE_REPO")")"
  image_tag="$(trim_whitespace "$(read_env_value "SEKANT_IMAGE_TAG")")"
  image_repo="${image_repo:-swastiksharmadev/sekant}"
  image_tag="${image_tag:-latest}"

  local init_secrets_image=""
  init_secrets_image="$(resolve_init_secrets_image "$image_repo" "$image_tag")"
  if docker image inspect "${init_secrets_image}" >/dev/null 2>&1; then
    printf "%s" "${init_secrets_image}"
    return 0
  fi

  if docker image inspect "sekant-init-secrets:latest" >/dev/null 2>&1; then
    printf "%s" "sekant-init-secrets:latest"
    return 0
  fi
  if docker image inspect "dashboard-init-secrets:latest" >/dev/null 2>&1; then
    printf "%s" "dashboard-init-secrets:latest"
    return 0
  fi
  printf "%s" "alpine:latest"
}

resolve_init_secrets_image() {
  local default_repo="$1"
  local default_tag="$2"
  local override_image=""
  local override_repo=""
  local override_tag=""

  override_image="$(trim_whitespace "$(read_env_value "SEKANT_INIT_SECRETS_IMAGE")")"
  if [[ -n "$override_image" ]]; then
    printf "%s" "$override_image"
    return 0
  fi

  override_repo="$(trim_whitespace "$(read_env_value "SEKANT_INIT_SECRETS_IMAGE_REPO")")"
  override_tag="$(trim_whitespace "$(read_env_value "SEKANT_INIT_SECRETS_IMAGE_TAG")")"
  override_repo="${override_repo:-$default_repo}"
  override_tag="${override_tag:-$default_tag}"
  printf "%s" "${override_repo}:init-secrets-${override_tag}"
}

read_volume_file() {
  local volume_name="$1"
  local file_path="$2"
  local helper_image
  helper_image="$(resolve_helper_image)"
  docker run --rm -v "${volume_name}:/vol" "$helper_image" sh -c "cat \"/vol/${file_path}\" 2>/dev/null || true"
}

write_volume_file() {
  local volume_name="$1"
  local file_path="$2"
  local helper_image
  helper_image="$(resolve_helper_image)"
  docker run -i --rm -v "${volume_name}:/vol" "$helper_image" sh -c "cat > \"/vol/${file_path}\""
}

installed_version=""
if (( has_existing_volumes == 1 )); then
  installed_version="$(read_volume_file "$secrets_volume_name" "dashboard_version" | tr -d '\r' | head -n 1 | xargs || true)"
  if [[ -n "${SEKANT_DASHBOARD_VERSION}" && -n "${installed_version}" && "${installed_version}" != "${SEKANT_DASHBOARD_VERSION}" ]]; then
    echo -e "${CYAN}${BOLD}Upgrade detected:${RESET} v${installed_version} -> v${SEKANT_DASHBOARD_VERSION}"
  fi
fi

seed_admin_username="admin"
seed_admin_password_default="admin@12345"
seed_admin_email=""
seed_admin_password="$seed_admin_password_default"
dashboard_https_port_default="443"
ingest_port_default="31415"
clickhouse_retention_days_default="700"
dashboard_https_port="$dashboard_https_port_default"
ingest_port="$ingest_port_default"
ingest_protocol="https"
clickhouse_retention_days="$clickhouse_retention_days_default"

can_reuse_env=0
if (( force_reconfigure == 0 )); then
  seed_admin_email_probe="$(trim_whitespace "$(read_env_value "KEYCLOAK_ADMIN_EMAIL")")"
  if [[ -n "$seed_admin_email_probe" ]]; then
    can_reuse_env=1
  fi
fi

if (( force_reconfigure == 0 && can_reuse_env == 1 )); then
  echo -e "${CYAN}${BOLD}Reusing existing setup values from .env (use --reconfigure to change).${RESET}"
  public_hostname="$(normalize_hostname "$(read_env_value "CADDY_DOMAIN")")"
  if [[ -z "$public_hostname" ]]; then
    public_hostname="localhost"
  fi
  clickhouse_mode="$(read_env_value "CLICKHOUSE_SETUP_MODE")"
  clickhouse_mode="${clickhouse_mode:-local}"
  seed_admin_email="$(read_env_value "KEYCLOAK_ADMIN_EMAIL")"
  seed_admin_email="$(trim_whitespace "$seed_admin_email")"
  if [[ -z "$seed_admin_email" ]]; then
    echo -e "${CYAN}${BOLD}Error:${RESET} KEYCLOAK_ADMIN_EMAIL is required but missing in .env." >&2
    echo "Run with --reconfigure to set the seeded admin email." >&2
    exit 1
  fi
  seed_admin_password="$(read_env_value "SEED_ADMIN_PASSWORD")"
  seed_admin_password="${seed_admin_password:-$seed_admin_password_default}"
  dashboard_https_port="$(read_env_value "DASHBOARD_HTTPS_PORT")"
  dashboard_https_port="${dashboard_https_port:-$dashboard_https_port_default}"
  ingest_port="$(read_env_value "INGEST_PORT")"
  ingest_port="${ingest_port:-$ingest_port_default}"
  clickhouse_retention_days="$(read_env_value "CLICKHOUSE_RETENTION_DAYS")"
  clickhouse_retention_days="${clickhouse_retention_days:-$clickhouse_retention_days_default}"
  if [[ "$seed_admin_password" == "$seed_admin_password_default" ]]; then
    echo -e "${CYAN}${BOLD}Note:${RESET} Seeded admin password changes are not applied via startup when reusing existing volumes."
    echo "Use the dashboard UI to reset the seeded admin password, or remove existing volumes for a fresh setup."
  fi
else
  echo ""
  echo -e "${CYAN}${BOLD}Hostname & Ports${RESET}"
  public_hostname="$(normalize_hostname "$(prompt_with_default_text "Domain / Hostname for Management Console (default: localhost) : " "localhost")")"
  dashboard_https_port="$(prompt_port_with_default_text "Dashboard HTTPS host port (default: ${dashboard_https_port_default}) : " "$dashboard_https_port_default")"
  ingest_port="$(prompt_port_with_default_text "Event Logging Port (default ${ingest_port_default}) : " "$ingest_port_default")"

  echo ""
  echo -e "${CYAN}${BOLD}Admin Credentials${RESET}"
  echo -e "Admin Username : ${seed_admin_username}"
  seed_admin_email="$(prompt_email_required "Admin Email : ")"
  seed_admin_password="$(prompt_secret_with_default_text "Admin Password (default : ${seed_admin_password_default}) : " "$seed_admin_password_default")"

  echo ""
  echo -e "${CYAN}${BOLD}Database${RESET}"
  clickhouse_mode="$(select_clickhouse_mode)"
  clickhouse_retention_days="$(prompt_retention_days_with_default_text "Data Retention Duration (in days) (default: ${clickhouse_retention_days_default}) : " "$clickhouse_retention_days_default")"
fi

write_env_value "CADDY_DOMAIN" "$public_hostname"
write_env_value "DASHBOARD_HTTPS_PORT" "$dashboard_https_port"

public_url="https://${public_hostname}"
if [[ "$dashboard_https_port" != "443" ]]; then
  public_url="https://${public_hostname}:${dashboard_https_port}"
fi
write_env_value "PUBLIC_URL" "$public_url"

write_env_value "INGEST_DOMAIN" "$public_hostname"
write_env_value "KEYCLOAK_ADMIN" "$seed_admin_username"
write_env_value "KEYCLOAK_ADMIN_EMAIL" "$seed_admin_email"
write_env_value "SEED_ADMIN_PASSWORD" "$seed_admin_password"
write_env_value "KEYCLOAK_HOSTNAME" "$public_hostname"
write_env_value "INGEST_PORT" "$ingest_port"
write_env_value "FLUENT_BIT_INPUT_PORT" "$ingest_port"
write_env_value "CLICKHOUSE_RETENTION_DAYS" "$clickhouse_retention_days"

if [[ "$dashboard_https_port" == "$ingest_port" ]]; then
  echo -e "${CYAN}${BOLD}Error:${RESET} Event logging port must be different from dashboard HTTPS port." >&2
  exit 1
fi

has_existing_runtime=0
if has_running_sekant_deployment; then
  has_existing_runtime=1
fi

if (( has_existing_volumes == 0 && has_existing_runtime == 0 )); then
  assert_port_free "$dashboard_https_port" "Dashboard HTTPS"
  assert_port_free "$ingest_port" "Ingestion HTTPS"
else
  if is_port_in_use "$dashboard_https_port"; then
    echo -e "${CYAN}${BOLD}Notice:${RESET} Dashboard HTTPS port ${dashboard_https_port} is already in use on 127.0.0.1. This is expected during upgrades if the existing Sekant deployment is running." >&2
  fi
  if is_port_in_use "$ingest_port"; then
    echo -e "${CYAN}${BOLD}Notice:${RESET} Event logging port ${ingest_port} is already in use on 127.0.0.1. This is expected during upgrades if the existing Sekant deployment is running." >&2
  fi
fi

if [[ "$clickhouse_mode" == "remote" ]]; then
  if (( has_existing_volumes == 1 && force_reconfigure == 0 )); then
    configure_remote_clickhouse_from_env
  else
    configure_remote_clickhouse
  fi
else
  configure_local_clickhouse
fi

if (( upgrade == 1 || has_existing_runtime == 1 )); then
  echo -e "${CYAN}${BOLD}Stopping existing containers (preserving volumes)...${RESET}"
  cd "$root_dir"
  run_compose down --remove-orphans
  if (( upgrade == 1 )); then
    remove_container_if_exists "sekant-superset"
    remove_container_if_exists "sekant-readiness"
    remove_container_if_exists "sekant-caddy"
    remove_container_if_exists "sekant-nginx"
    remove_container_if_exists "sekant-frontend"
    remove_container_if_exists "sekant-backend"
    remove_container_if_exists "sekant-keycloak"
    remove_container_if_exists "sekant-redis"
    remove_container_if_exists "sekant-sql-validator"
    remove_container_if_exists "sekant-clickhouse"
    remove_container_if_exists "sekant-postgres"
    remove_container_if_exists "sekant-fluent-bit"
    remove_container_if_exists "sekant-init-secrets"
  fi
fi

echo
echo -e "${GREEN}${BOLD}Starting Sekant Management Console Platform...${RESET}"
echo
cd "$root_dir"

sekant_image_repo="$(trim_whitespace "$(read_env_value "SEKANT_IMAGE_REPO")")"
sekant_image_tag="$(trim_whitespace "$(read_env_value "SEKANT_IMAGE_TAG")")"
sekant_image_repo="${sekant_image_repo:-sekantsec/management-console}"
sekant_image_tag="${sekant_image_tag:-latest}"
init_secrets_image="$(resolve_init_secrets_image "$sekant_image_repo" "$sekant_image_tag")"

if [[ "$sekant_image_repo" != */* ]]; then
  if ! docker image inspect "$init_secrets_image" >/dev/null 2>&1; then
    echo -e "${CYAN}${BOLD}Error:${RESET} SEKANT_IMAGE_REPO must be a namespaced Docker repo (e.g. swastiksharmadev/sekant)." >&2
    echo "Current SEKANT_IMAGE_REPO=${sekant_image_repo}" >&2
    echo "Update .env (SEKANT_IMAGE_REPO / SEKANT_IMAGE_TAG) to point at your pushed images, then re-run start.sh." >&2
    exit 1
  fi
else
  required_images=(
    "${sekant_image_repo}:backend-${sekant_image_tag}"
    "${sekant_image_repo}:frontend-${sekant_image_tag}"
    "${sekant_image_repo}:nginx-${sekant_image_tag}"
    "${sekant_image_repo}:sql-validator-${sekant_image_tag}"
    "${init_secrets_image}"
  )
  missing_images=0
  for image_name in "${required_images[@]}"; do
    if ! docker image inspect "${image_name}" >/dev/null 2>&1; then
      missing_images=1
      break
    fi
  done

  if (( missing_images == 0 )); then
  if (( quiet == 0 )); then
    echo "Using locally available Docker images for ${sekant_image_repo}:${sekant_image_tag} (skipping pull)..." >&2
  fi
  else
    if (( quiet == 0 )); then
      echo "Pulling Docker images from ${sekant_image_repo}..." >&2
    fi
    set +e
    run_compose pull
    set -e
  fi
fi

if compose_service_has_build "init-secrets"; then
  set +e
  run_compose build init-secrets
  build_init_secrets_status=$?
  set -e
  if (( build_init_secrets_status != 0 )); then
    if (( quiet == 1 )); then
      echo -e "${CYAN}${BOLD}Error:${RESET} Upgrade failed. Re-run with --verbose to see details." >&2
    else
      echo -e "${CYAN}${BOLD}Error:${RESET} Failed to build init-secrets image." >&2
    fi
    exit "$build_init_secrets_status"
  fi
else
  if ! ensure_image_available "$init_secrets_image"; then
    if (( quiet == 1 )); then
      echo -e "${CYAN}${BOLD}Error:${RESET} Upgrade failed. Re-run with --verbose to see details." >&2
    else
      echo -e "${CYAN}${BOLD}Error:${RESET} Missing required Docker image: ${init_secrets_image}" >&2
      if [[ -f "${root_dir}/load-images.sh" ]]; then
        echo "Run ./load-images.sh (or docker load the provided images) and re-run start.sh." >&2
      else
        echo "Make sure the image exists in your registry and SEKANT_IMAGE_REPO / SEKANT_IMAGE_TAG are correct in .env, then re-run start.sh." >&2
      fi
    fi
    exit 1
  fi
fi

init_secrets_check_image="$init_secrets_image"
if ! docker run --rm "${init_secrets_check_image}" sh -c "grep -q \"Caddyfile prepared successfully\" /usr/local/bin/init-secrets.sh"; then
  echo -e "${CYAN}${BOLD}Error:${RESET} init-secrets image is missing the required upgrade logic." >&2
  echo "Update SEKANT_IMAGE_REPO / SEKANT_IMAGE_TAG (or SEKANT_INIT_SECRETS_IMAGE*) to a newer image, then re-run start.sh." >&2
  exit 1
fi

set +e
run_compose up -d --remove-orphans "${compose_up_args[@]+"${compose_up_args[@]}"}"
compose_status=$?
set -e

has_service_args=0
for arg in "${compose_up_args[@]+"${compose_up_args[@]}"}"; do
  if [[ "$arg" != -* ]]; then
    has_service_args=1
    break
  fi
done
if (( compose_status == 0 && has_service_args == 0 )); then
  set +e
  wait_for_sekant_ready
  wait_status=$?
  set -e
  if (( wait_status != 0 )); then
    compose_status=1
  else
    if ! ensure_clickhouse_retention_ttl; then
      compose_status=1
    fi
  fi
fi

if (( compose_status != 0 )); then
  if (( quiet == 1 )); then
    echo -e "${CYAN}${BOLD}Fixing${RESET}" >&2
  else
    echo -e "${CYAN}${BOLD}Error:${RESET} Startup failed. Collecting diagnostics..." >&2
    run_compose ps 2>/dev/null || true
  fi

    init_secrets_logs="$("${compose_cmd[@]}" logs --no-color --tail 120 init-secrets 2>/dev/null || true)"
    if echo "$init_secrets_logs" | grep -Eqi 'exec format error|no matching manifest|platform .* does not match|rosetta'; then
      if (( quiet == 1 )); then
        echo -e "${CYAN}${BOLD}Error:${RESET} init-secrets failed to start due to an image/architecture mismatch." >&2
        echo "On Apple Silicon, enable x86/amd64 emulation in Docker Desktop (Rosetta) or use an arm64 build." >&2
        echo "Re-run with --verbose for full logs." >&2
      fi
    fi

  secrets_has_caddyfile="$(read_volume_file "$secrets_volume_name" "Caddyfile" | head -n 1 | tr -d '\r' | xargs || true)"
  if (( upgrade == 1 )); then
    attempted_recovery=0

    if [[ -z "$secrets_has_caddyfile" ]]; then
      attempted_recovery=1
      if (( upgrade == 1 )); then
        load_distribution_images || true
      fi
      if (( quiet == 0 )); then
        echo "Secrets volume does not contain Caddyfile. Recreating init-secrets (preserving volumes)..." >&2
      fi
      set +e
      run_compose up -d --force-recreate init-secrets
      set -e
    fi

    set +e
    nginx_logs="$("${compose_cmd[@]}" logs --no-color --tail 200 nginx 2>/dev/null)"
    if (( quiet == 1 )); then
      printf "%s\n" "$nginx_logs" >>"$upgrade_log_file" 2>/dev/null || true
    fi
    set -e
    if echo "$nginx_logs" | grep -q 'host not found in upstream "superset"'; then
      attempted_recovery=1
      if (( quiet == 0 )); then
        echo "Fixing nginx..." >&2
      fi
      set +e
      if compose_service_has_build "nginx"; then
        run_compose build --no-cache nginx
      fi
      run_compose up -d --force-recreate nginx
      set -e
    fi

    if (( attempted_recovery == 1 )); then
      set +e
      run_compose up -d --remove-orphans "${compose_up_args[@]+"${compose_up_args[@]}"}"
      compose_retry_status=$?
      set -e
      if (( compose_retry_status == 0 )); then
        if (( has_service_args == 0 )); then
          set +e
          wait_for_sekant_ready
          wait_retry_status=$?
          set -e
          if (( wait_retry_status == 0 )); then
            compose_status=0
          else
            compose_status=1
          fi
        else
          compose_status=0
        fi
      else
        compose_status=$compose_retry_status
      fi
    fi
  fi

  if (( compose_status != 0 )); then
    if (( quiet == 0 )); then
      run_compose logs --no-color --tail 200 init-secrets 2>/dev/null || true
      run_compose logs --no-color --tail 200 postgres 2>/dev/null || true
      run_compose logs --no-color --tail 200 nginx 2>/dev/null || true
      run_compose logs --no-color --tail 200 backend 2>/dev/null || true
      run_compose logs --no-color --tail 200 keycloak 2>/dev/null || true
    else
      echo -e "${CYAN}${BOLD}Error:${RESET} Upgrade failed. Re-run with --verbose to see details." >&2
    fi
    exit "$compose_status"
  fi
fi

if [[ -n "${SEKANT_DASHBOARD_VERSION}" ]]; then
  printf "%s" "${SEKANT_DASHBOARD_VERSION}" | write_volume_file "$secrets_volume_name" "dashboard_version" || true
fi

echo
echo -e "${CYAN}${BOLD}Dashboard URL:${RESET} ${public_url}"
echo

if [[ -n "$upgrade_log_file" ]]; then
  rm -f "$upgrade_log_file" 2>/dev/null || true
fi
