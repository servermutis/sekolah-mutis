#!/usr/bin/env bash
# Uji skema + RLS pada Postgres lokal (stub Supabase). Pakai: scripts/test-db.sh [host-socket] [port]
# Setiap berkas uji dijalankan pada database baru.
set -euo pipefail
cd "$(dirname "$0")/.."
H=${1:-/tmp/pgtest}; PORT=${2:-54329}
P0="psql -h $H -p $PORT -U postgres -q -v ON_ERROR_STOP=1"
for tf in supabase/tests/[1-9]*.sql; do
  echo "##### $tf"
  $P0 -d postgres -c "drop database if exists t" -c "create database t" >/dev/null 2>&1
  P="$P0 -d t"
  for f in supabase/tests/00_stub_supabase.sql supabase/migrations/*.sql "$tf"; do $P -f "$f" 2>&1 | grep -v '^$' || true; done
done
