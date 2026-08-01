#!/bin/bash
# Physical base backup of the primary. Run from the primary host.
# Schedule via cron, e.g. daily at 02:00:
#   0 2 * * * /path/to/scripts/backup.sh >> /var/log/pg_backup.log 2>&1
set -euo pipefail

BACKUP_ROOT="${BACKUP_ROOT:-/backup}"
CONTAINER="${CONTAINER:-postgres_primary}"
RETENTION_DAYS="${RETENTION_DAYS:-7}"
STAMP="$(date +%Y%m%d-%H%M%S)"
DEST="$BACKUP_ROOT/$STAMP"

# Load POSTGRES_USER from the project .env if present
if [ -f "$(dirname "$0")/../.env" ]; then
  set -a
  # shellcheck disable=SC1091
  . "$(dirname "$0")/../.env"
  set +a
fi
PG_USER="${POSTGRES_USER:-postgres}"

echo ">>> Starting base backup to $DEST"
mkdir -p "$DEST"

docker exec "$CONTAINER" pg_basebackup \
  -U "$PG_USER" \
  -D - \
  -Ft \
  -z \
  -P \
  > "$DEST/base.tar.gz"

echo ">>> Backup complete: $DEST/base.tar.gz"

echo ">>> Pruning backups older than ${RETENTION_DAYS} days"
find "$BACKUP_ROOT" -maxdepth 1 -type d -name '20*' -mtime "+${RETENTION_DAYS}" -exec rm -rf {} +

echo ">>> Done."
