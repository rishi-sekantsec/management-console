#!/bin/sh
set -eu

postgres_pid=""

forward_signal() {
  if [ -n "$postgres_pid" ] && kill -0 "$postgres_pid" 2>/dev/null; then
    kill -TERM "$postgres_pid" 2>/dev/null || true
  fi
}

trap forward_signal INT TERM

wait_for_postgres() {
  attempts=0
  max_attempts="${POSTGRES_PASSWORD_RECONCILE_MAX_ATTEMPTS:-120}"

  while :; do
    if [ -n "$postgres_pid" ] && ! kill -0 "$postgres_pid" 2>/dev/null; then
      wait "$postgres_pid"
      exit $?
    fi

    if psql -v ON_ERROR_STOP=1 -U "${POSTGRES_USER:-postgres}" -d postgres -Atqc "SELECT 1" >/dev/null 2>&1; then
      return 0
    fi

    attempts=$((attempts + 1))
    if [ "$attempts" -ge "$max_attempts" ]; then
      echo "Timed out waiting for postgres to accept local connections for password reconciliation." >&2
      return 1
    fi

    sleep 1
  done
}

reconcile_password() {
  password_file="${POSTGRES_PASSWORD_FILE:-}"
  if [ -z "$password_file" ] || [ ! -f "$password_file" ]; then
    return 0
  fi

  db_password="$(cat "$password_file")"
  if [ -z "$db_password" ]; then
    return 0
  fi

  db_user="${POSTGRES_USER:-postgres}"
  escaped_user="$(printf '%s' "$db_user" | sed 's/"/""/g')"
  escaped_password="$(printf '%s' "$db_password" | sed "s/'/''/g")"

  psql -v ON_ERROR_STOP=1 -U "$db_user" -d postgres -c "ALTER ROLE \"$escaped_user\" WITH PASSWORD '$escaped_password';" >/dev/null
}

docker-entrypoint.sh postgres &
postgres_pid=$!

if wait_for_postgres; then
  reconcile_password
else
  forward_signal
  wait "$postgres_pid" || true
  exit 1
fi

wait "$postgres_pid"
