# Production Deployment Guide

> Production config files are separated from PoC files. They do not affect the existing setup.

## Files

| File | Purpose |
| --- | --- |
| `docker-compose-primary.prod.yml` | Primary Postgres |
| `docker-compose-replica.prod.yml` | Replica Postgres (one file per server) |
| `docker-compose-pgbouncer.prod.yml` | Connection pooler for app traffic |
| `docker-compose-monitoring.prod.yml` | Prometheus postgres_exporter |
| `docker-compose-pgadmin.prod.yml` | pgAdmin web UI (loopback only, front with TLS) |
| `primary/postgresql.prod.conf` | Primary tuning (defaults for ~8GB RAM) |
| `primary/pg_hba.prod.conf` | Production access rules (deny remote by default) |
| `replica/postgresql.prod.conf` | Replica tuning |
| `replica/replica-entrypoint.prod.sh` | Replica bootstrap + per-replica slot |
| `.env.prod.example` | Production environment template |
| `scripts/backup.sh` | Daily physical backup |
| `scripts/health-check.sh` | Replication health report |

## 1. Prepare Secrets

On **every server**:

```bash
cp .env.prod.example .env
chmod 600 .env
```

Generate three separate passwords:

```bash
openssl rand -base64 32
openssl rand -base64 32
openssl rand -base64 32
```

Fill `POSTGRES_PASSWORD`, `REPLICATION_PASSWORD`, and `APP_PASSWORD` in `.env`. The `REPLICATION_PASSWORD` must match on primary and all replicas.

Never commit `.env`.

## 2. Configure Network Access

Edit `primary/pg_hba.prod.conf` on the primary. Uncomment/add exact IPs:

```text
host    replication     replicator      10.0.1.20/32            scram-sha-256
host    replication     replicator      10.0.1.30/32            scram-sha-256
host    all             app             10.0.2.0/24             scram-sha-256
host    all             postgres        10.0.0.10/32            scram-sha-256
```

Firewall example (primary host):

```bash
ufw default deny incoming
ufw allow from 10.0.1.20 to any port 5432 proto tcp
ufw allow from 10.0.1.30 to any port 5432 proto tcp
ufw allow from 10.0.2.0/24 to any port 5432 proto tcp
```

Do not use `0.0.0.0/0` for PostgreSQL in production.

## 3. Tune Hardware

`primary/postgresql.prod.conf` and `replica/postgresql.prod.conf` assume ~8GB RAM and SSD. Adjust:

```conf
shared_buffers = 2GB            # about 25% RAM
effective_cache_size = 6GB      # about 75% RAM
work_mem = 32MB                 # consider active queries, not only connections
maintenance_work_mem = 512MB
random_page_cost = 1.1          # SSD; use 4.0 for HDD
```

Also update Compose resource limits to match the server.

## 4. Start Primary

```bash
mkdir -p archive
docker compose -f docker-compose-primary.prod.yml config
docker compose -f docker-compose-primary.prod.yml up -d
docker logs -f postgres_primary
```

## 5. Start Replicas

On replica 1 `.env`:

```bash
PRIMARY_HOST=10.0.1.10
REPLICA_SLOT=replica_slot_1
REPLICA_NAME=replica_1
```

On replica 2 `.env`:

```bash
PRIMARY_HOST=10.0.1.10
REPLICA_SLOT=replica_slot_2
REPLICA_NAME=replica_2
```

Then on each replica:

```bash
docker compose -f docker-compose-replica.prod.yml config
docker compose -f docker-compose-replica.prod.yml up -d
docker logs -f postgres_replica
```

Every replica must use a unique `REPLICA_SLOT` and `REPLICA_NAME`.

## 6. Verify Replication

```bash
bash scripts/health-check.sh
```

Expected:

- One row per replica in `pg_stat_replication`
- Every slot in `pg_replication_slots` has `active = t`
- `lag_bytes` stays low under normal load

On each replica:

```bash
docker exec postgres_replica psql -U postgres -c "SELECT pg_is_in_recovery();"
```

Must return `t`.

## 7. Connection Pooling

Run PgBouncer where application traffic enters:

```bash
docker compose -f docker-compose-pgbouncer.prod.yml config
docker compose -f docker-compose-pgbouncer.prod.yml up -d
```

Application connection:

```text
postgresql://app:<APP_PASSWORD>@<pgbouncer-host>:6432/<POSTGRES_DB>
```

## 8. Monitoring

Run exporter on the primary/replica host. If deployed as a separate Compose project, change `DATA_SOURCE_NAME` in `docker-compose-monitoring.prod.yml` to the real Postgres host IP.

```bash
docker compose -f docker-compose-monitoring.prod.yml up -d
curl http://localhost:9187/metrics
```

Configure Prometheus to scrape `<host>:9187`.

Recommended alerts:

- Replica disconnected (`pg_stat_replication` row missing)
- Replication lag above 60 seconds / 100MB
- Inactive replication slot
- Disk usage above 80%
- Long-running queries above 60 seconds
- Connection utilization above 80%
- Backup older than 24 hours

## 9. pgAdmin (Optional)

pgAdmin exposes an admin web UI for the cluster. In production it must never be reachable from the public internet directly.

Prepare credentials in `.env`:

```bash
PGADMIN_EMAIL=admin@yourcompany.com
PGADMIN_PASSWORD=<use openssl rand -base64 32>
```

Start:

```bash
docker compose -f docker-compose-pgadmin.prod.yml up -d
```

Access:

- The stack binds `127.0.0.1:5050` by default — reachable only from the host.
- For remote access, front it with nginx/Traefik + TLS + VPN or SSO. Never publish port 5050 directly.
- Server mode and master password are enabled — every user has their own login inside pgAdmin.

Register servers manually inside the UI (Host = primary/replica IP, Port = 5432, User = `postgres` or `app`).

## 10. Backup

Local backups alone are not sufficient. Send backups to separate storage (S3, object storage, NAS) with encryption and retention.

Daily backup example:

```bash
BACKUP_ROOT=/mnt/backup RETENTION_DAYS=7 bash scripts/backup.sh
```

Cron (daily 02:17):

```cron
17 2 * * * cd /opt/postgres-cluster && BACKUP_ROOT=/mnt/backup bash scripts/backup.sh >> /var/log/pg-backup.log 2>&1
```

Restore-test backups regularly. A backup without a successful restore test is not a verified backup.

### Point-in-Time Recovery (PITR)

1. Mount durable `/archive` storage (already present in primary prod Compose).
2. Uncomment `archive_mode`, `archive_command`, and `archive_timeout` in `primary/postgresql.prod.conf`.
3. Restart primary.
4. Copy WAL archives to off-host storage.

For larger production systems, use pgBackRest or WAL-G instead of the sample local archive command.

## 11. TLS

Create certificates using your internal CA. Do not use self-signed certificates for untrusted networks.

1. Put files at `certs/server.crt` and `certs/server.key`.
2. Set private key permission to `0600` and ownership readable by UID `999` in the container.
3. Uncomment TLS volumes in the production Compose files.
4. Uncomment `ssl` settings in `*.prod.conf`.
5. Change client rules from `host` to `hostssl` in `pg_hba.prod.conf`.
6. Use `sslmode=verify-full` with CA verification on clients and replicas.

## 12. Failover

These Compose files provide replication, **not automatic failover**. Manual promotion:

```bash
docker exec postgres_replica pg_ctl promote -D /var/lib/postgresql/data
```

Manual promotion does not redirect applications or safely rebuild the old primary. For automatic production failover, use Patroni + etcd/Consul, CloudNativePG on Kubernetes, or a managed PostgreSQL service.

## 13. Deployment Checklist

- [ ] Unique secure passwords stored outside Git
- [ ] `pg_hba.prod.conf` restricted to exact IPs/subnets
- [ ] Host firewall restricted
- [ ] TLS enabled and verified
- [ ] Memory settings match server RAM
- [ ] Unique replica slot/name per replica
- [ ] Backups stored off-host
- [ ] Restore test completed
- [ ] WAL/PITR enabled
- [ ] Metrics and alerts enabled
- [ ] Failover process tested
- [ ] OS/kernel/disk monitoring enabled
- [ ] PostgreSQL minor image update process documented
