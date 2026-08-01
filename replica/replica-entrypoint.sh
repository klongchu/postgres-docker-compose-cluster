#!/bin/bash
set -e

: "${PRIMARY_HOST:?PRIMARY_HOST is required}"
: "${REPLICATION_USER:?REPLICATION_USER is required}"
: "${REPLICATION_PASSWORD:?REPLICATION_PASSWORD is required}"
REPLICA_SLOT="${REPLICA_SLOT:-replica_slot_1}"

echo ">>> Waiting for primary ($PRIMARY_HOST) to be ready..."
until pg_isready -h "$PRIMARY_HOST" -p 5432 -U "$REPLICATION_USER"; do
  echo "    Primary not ready — retrying in 2s..."
  sleep 2
done

# Only bootstrap if this is a fresh data directory. Restarting an
# already-initialized replica should not re-run pg_basebackup.
if [ -z "$(ls -A /var/lib/postgresql/data 2>/dev/null)" ]; then
  echo ">>> Ensuring replication slot '$REPLICA_SLOT' exists on primary..."
  SLOT_EXISTS=$(PGPASSWORD="$REPLICATION_PASSWORD" psql -h "$PRIMARY_HOST" -U "$REPLICATION_USER" -d postgres -tAc \
    "SELECT 1 FROM pg_replication_slots WHERE slot_name='$REPLICA_SLOT'")
  if [ "$SLOT_EXISTS" != "1" ]; then
    PGPASSWORD="$REPLICATION_PASSWORD" psql -h "$PRIMARY_HOST" -U "$REPLICATION_USER" -d postgres -c \
      "SELECT pg_create_physical_replication_slot('$REPLICA_SLOT')"
  fi

  echo ">>> Taking base backup from primary using slot '$REPLICA_SLOT'..."
  PGPASSWORD="$REPLICATION_PASSWORD" pg_basebackup \
    -h "$PRIMARY_HOST" \
    -U "$REPLICATION_USER" \
    -D /var/lib/postgresql/data \
    -P \
    -Xs \
    -R \
    --slot="$REPLICA_SLOT"

  echo ">>> Base backup complete. Overlaying replica config..."
  cp /etc/replica/postgresql.conf /var/lib/postgresql/data/postgresql.conf
else
  echo ">>> Existing data directory found. Skipping base backup."
fi

echo ">>> Starting replica in hot standby mode..."
exec docker-entrypoint.sh postgres
