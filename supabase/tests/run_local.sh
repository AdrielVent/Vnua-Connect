#!/usr/bin/env bash
# Runs the migrations + security tests against a throwaway local Postgres (no Docker needed).
# Requires: brew install postgresql@17
set -euo pipefail
cd "$(dirname "$0")/.."
PG="$(brew --prefix postgresql@17)/bin"
DIR="$(mktemp -d)"
PORT=54329
trap '"$PG/pg_ctl" -D "$DIR" -m immediate stop >/dev/null 2>&1 || true; rm -rf "$DIR"' EXIT

"$PG/initdb" -D "$DIR" -U postgres --auth=trust >/dev/null
"$PG/pg_ctl" -D "$DIR" -o "-p $PORT -k $DIR" -l "$DIR/log" start >/dev/null
PSQL=("$PG/psql" -h "$DIR" -p "$PORT" -U postgres -d postgres -v ON_ERROR_STOP=1 -q -o /dev/null)

"${PSQL[@]}" -f tests/local_supabase_shim.sql
for m in migrations/*.sql; do "${PSQL[@]}" -f "$m"; done
"${PSQL[@]}" -f tests/security_test.sql
