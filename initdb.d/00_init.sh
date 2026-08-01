#!/bin/bash
set -e

# Create replication user (for streaming replication)
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
  DO \$\$
  BEGIN
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = '${REPLICATION_USER}') THEN
      CREATE ROLE ${REPLICATION_USER} WITH REPLICATION LOGIN PASSWORD '${REPLICATION_PASSWORD}';
    END IF;
  END
  \$\$;
EOSQL

# Create application user (optional — for app connections)
if [ -n "$APP_USER" ] && [ -n "$APP_PASSWORD" ]; then
  psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    DO \$\$
    BEGIN
      IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = '${APP_USER}') THEN
        CREATE ROLE ${APP_USER} WITH LOGIN PASSWORD '${APP_PASSWORD}';
      END IF;
    END
    \$\$;
    GRANT CONNECT ON DATABASE ${POSTGRES_DB} TO ${APP_USER};
    GRANT USAGE ON SCHEMA public TO ${APP_USER};
    ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO ${APP_USER};
    ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO ${APP_USER};
EOSQL
  echo ">>> Created app user: $APP_USER"
fi

echo ">>> Created replication user: $REPLICATION_USER"
