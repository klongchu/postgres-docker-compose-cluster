#!/bin/bash
# Quick replication health report. Run from the primary host.
set -euo pipefail

CONTAINER="${CONTAINER:-postgres_primary}"

if [ -f "$(dirname "$0")/../.env" ]; then
  set -a
  # shellcheck disable=SC1091
  . "$(dirname "$0")/../.env"
  set +a
fi
PG_USER="${POSTGRES_USER:-postgres}"

echo "=== Connected replicas (pg_stat_replication) ==="
docker exec "$CONTAINER" psql -U "$PG_USER" -x -c "
SELECT client_addr, application_name, state, sync_state,
       pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn) AS lag_bytes,
       EXTRACT(EPOCH FROM (now() - reply_time))::int AS lag_seconds
FROM pg_stat_replication;"

echo "=== Replication slots (pg_replication_slots) ==="
docker exec "$CONTAINER" psql -U "$PG_USER" -c "
SELECT slot_name, active, restart_lsn FROM pg_replication_slots;"

echo "=== Long-running queries (> 5s) ==="
docker exec "$CONTAINER" psql -U "$PG_USER" -x -c "
SELECT pid, now() - query_start AS duration, state, query
FROM pg_stat_activity
WHERE state = 'active' AND now() - query_start > interval '5 seconds'
ORDER BY duration DESC;"
