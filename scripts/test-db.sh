#!/usr/bin/env bash
# Applique les migrations sur une base Postgres + PostGIS jetable puis lance
# les tests SQL de supabase/tests. La tâche planifiée (pg_cron) est ignorée.
#
#   PGHOST=... PGPORT=... PGUSER=postgres scripts/test-db.sh
set -euo pipefail
cd "$(dirname "$0")/.."

DB=${TEST_DB:-contamination_test}
PSQL=(psql -X -q -v ON_ERROR_STOP=1)

"${PSQL[@]}" -d postgres -c "drop database if exists $DB" -c "create database $DB" \
  -c "alter database $DB set search_path = \"\$user\", public, extensions"
"${PSQL[@]}" -d "$DB" -f supabase/tests/supabase_stubs.sql
for f in supabase/migrations/*.sql; do
  [[ $f == *_schedule.sql ]] && continue
  echo "migration: $f"
  "${PSQL[@]}" -d "$DB" -f "$f"
done
for f in supabase/tests/test_*.sql; do
  echo "test: $f"
  "${PSQL[@]}" -d "$DB" -o /dev/null -f "$f"
done
echo "OK"
