#!/bin/bash
set -e

echo ">>> Waiting for primary to be ready..."
until pg_isready -h postgres-primary -p 5432 -U postgres; do
  echo "    Primary not ready — retrying in 2s..."
  sleep 2
done

echo ">>> Primary is ready. Clearing data directory..."
rm -rf /var/lib/postgresql/data/*

echo ">>> Taking base backup from primary..."
PGPASSWORD=replicator_password pg_basebackup \
  -h postgres-primary \
  -U replicator \
  -D /var/lib/postgresql/data \
  -P \
  -Xs \
  -R

# -P  shows progress
# -Xs streams WAL during the backup (avoids needing a replication slot)
# -R  writes standby.signal and recovery settings automatically

echo ">>> Base backup complete. Overlaying replica config..."
cp /etc/replica/postgresql.conf /var/lib/postgresql/data/postgresql.conf

echo ">>> Starting replica in hot standby mode..."
exec docker-entrypoint.sh postgres