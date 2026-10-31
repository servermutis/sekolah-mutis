#!/usr/bin/env bash
# Nyalakan Postgres lokal untuk pengujian (socket /tmp/pgtest, port 54329) bila belum hidup.
H=/tmp/pgtest; PORT=54329
psql -h $H -p $PORT -U postgres -d postgres -Atc "select 1" >/dev/null 2>&1 && { echo "Postgres sudah hidup"; exit 0; }
rm -f $H/data/postmaster.pid
su postgres -c "/usr/lib/postgresql/16/bin/pg_ctl -D $H/data -l $H/log -o '-k $H -p $PORT' start" >/dev/null 2>&1
sleep 3; psql -h $H -p $PORT -U postgres -d postgres -Atc "select 'Postgres hidup'"
