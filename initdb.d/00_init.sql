-- Create replication role if it doesn't exist
DO $$ BEGIN
  IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'replica') THEN
    CREATE ROLE replica WITH REPLICATION LOGIN PASSWORD '${POSTGRES_PASSWORD}';
  END IF;
END $$;

-- Replication slots are created per-replica via pg_basebackup --create-slot
-- Each replica must set a unique REPLICA_SLOT name in its .env
