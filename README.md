# PostgreSQL 17 Cluster พร้อม Read Replica

![Docker](https://img.shields.io/badge/Docker-27.2.0-orange)
![Docker Compose](https://img.shields.io/badge/Docker%20Compose-v1.29.2--desktop.2-orange)
![PostgreSQL](https://img.shields.io/badge/PostgreSQL-17-green)

## ภาพรวม

Docker Compose ชุดนี้สร้าง PostgreSQL 17 cluster ที่มี primary (read-write) หนึ่งตัว และ read replica ตั้งแต่หนึ่งตัวขึ้นไป โดยใช้ **physical streaming replication** พร้อม replication slot แยกต่อ replica

**รูปแบบการติดตั้ง:**

- **แบบเครื่องเดียว** ([docker-compose.yml](docker-compose.yml)) — primary และ replica อยู่บนเครื่องเดียวกัน
- **แบบแยกเซิร์ฟเวอร์** ([docker-compose-primary.yml](docker-compose-primary.yml) + [docker-compose-replica.yml](docker-compose-replica.yml)) — primary กับ replica อยู่คนละ physical server / VM รองรับ 1 primary + หลาย replica

![Docker-compose Stack](docs/docker-compose-stack.png)

## โครงสร้างไฟล์

```text
.
├── docker-compose.yml              # เครื่องเดียว
├── docker-compose-primary.yml      # primary (แยกเครื่อง)
├── docker-compose-replica.yml      # replica (แยกเครื่อง)
├── .env.example                    # template สำหรับ environment
├── primary/
│   ├── postgresql.conf             # config primary
│   └── pg_hba.conf                 # authentication rules
├── replica/
│   ├── postgresql.conf             # config replica (hot standby)
│   └── replica-entrypoint.sh       # bootstrap script
└── initdb.d/
    └── 00_init.sh                  # สร้าง replication user + app user
```

## ⚠️ ข้อควรระวังสำคัญ

> **setup นี้เป็น Proof of Concept (PoC) ไม่แนะนำสำหรับ production โดยตรง**

สำหรับ production ควรพิจารณา: SSL/TLS, จำกัด CIDR ใน `pg_hba.conf`, backup, monitoring, connection pooler (PgBouncer/PgCat), failover automation

## สถาปัตยกรรม

```text
                    ┌─────────────┐
                    │   PRIMARY   │  read-write
                    └──────┬──────┘
                           │ WAL streaming
                  ┌────────┴────────┐
                  ▼                 ▼
          ┌─────────────┐   ┌─────────────┐
          │  REPLICA 1  │   │  REPLICA 2  │  read-only
          └─────────────┘   └─────────────┘
```

Primary เขียน WAL แล้ว replica แต่ละตัว stream WAL ผ่าน slot ของตัวเอง (`replica_slot_1`, `replica_slot_2`, ...) primary จะไม่ลบ WAL จนกว่า replica ทุกตัวจะ apply ครบ

## Environment Variables

จาก [.env.example](.env.example):

| ตัวแปร | ใช้บน | ค่าตัวอย่าง |
| --- | --- | --- |
| `POSTGRES_USER` / `POSTGRES_PASSWORD` / `POSTGRES_DB` | primary | postgres |
| `REPLICATION_USER` / `REPLICATION_PASSWORD` | primary + replica | replicator |
| `APP_USER` / `APP_PASSWORD` | primary (optional) | app |
| `PRIMARY_HOST` | replica | `postgres_primary` หรือ IP จริง |
| `REPLICA_SLOT` | replica | `replica_slot_1` (ไม่ซ้ำต่อ replica) |

---

## เริ่มต้นแบบเครื่องเดียว

```bash
git clone git@github.com:luismr/postgres-docker-compose-cluster.git
cd postgres-docker-compose-cluster
cp .env.example .env
docker-compose up -d
```

**Port:**

- Primary: `localhost:5432`
- Replica: `localhost:5433`

---

## เริ่มต้นแบบแยกเซิร์ฟเวอร์ (1 Primary)

### สิ่งที่ต้องมี

- Server อย่างน้อย 2 เครื่องที่ติดตั้ง Docker + Docker Compose
- Network ที่เชื่อมถึงกันได้ ระหว่างเครื่อง primary กับ replica
- Firewall ของ primary เปิด TCP port 5432 ให้ IP ของ replica

### เซิร์ฟเวอร์ 1 (Primary)

1. Clone และตั้งค่า `.env`:

```bash
git clone git@github.com:luismr/postgres-docker-compose-cluster.git
cd postgres-docker-compose-cluster
cp .env.example .env
# แก้ password ให้แข็งแรง
```

1. **จำกัด IP ใน [primary/pg_hba.conf](primary/pg_hba.conf)** เปลี่ยน `0.0.0.0/0` เป็น IP ของ replica:

```text
host    replication     replicator      192.168.1.20/32         scram-sha-256
host    replication     replicator      192.168.1.30/32         scram-sha-256
host    all             all             192.168.1.0/24          scram-sha-256
```

1. เริ่ม primary:

```bash
docker-compose -f docker-compose-primary.yml up -d
```

1. หา IP ของเครื่อง primary (`ip addr` / `ipconfig`) เช่น `192.168.1.10`

### เซิร์ฟเวอร์ 2 (Replica 1)

1. Clone repo แล้วสร้าง `.env`:

```bash
cp .env.example .env
```

แก้ค่า:

```bash
PRIMARY_HOST=192.168.1.10
REPLICA_SLOT=replica_slot_1
REPLICATION_USER=replicator
REPLICATION_PASSWORD=<ตรงกับ primary>
```

1. เริ่ม replica:

```bash
docker-compose -f docker-compose-replica.yml up -d
docker-compose -f docker-compose-replica.yml logs -f
```

ในล็อกต้องเห็น:

- `>>> Waiting for primary (192.168.1.10) to be ready...`
- `>>> Ensuring replication slot 'replica_slot_1' exists on primary...`
- `>>> Taking base backup from primary using slot 'replica_slot_1'...`
- `>>> Starting replica in hot standby mode...`

---

## เพิ่ม Replica ตัวที่ 2, 3, ... (3 เซิร์ฟเวอร์ขึ้นไป)

`max_wal_senders=10` และ `max_replication_slots=10` ใน [primary/postgresql.conf](primary/postgresql.conf) รองรับ replica ได้สูงสุด 10 ตัวโดยไม่ต้องแก้อะไร

**สำหรับแต่ละ replica เพิ่มใหม่:**

1. เพิ่ม IP ของ replica ตัวใหม่ใน [primary/pg_hba.conf](primary/pg_hba.conf) แล้ว reload:

```bash
docker exec postgres_primary psql -U postgres -c "SELECT pg_reload_conf();"
```

1. บนเซิร์ฟเวอร์ replica ใหม่ ตั้ง `.env` โดยใช้ **`REPLICA_SLOT` ที่ไม่ซ้ำ**:

```bash
PRIMARY_HOST=192.168.1.10
REPLICA_SLOT=replica_slot_2      # หรือ 3, 4, ...
```

1. `docker-compose -f docker-compose-replica.yml up -d`

**⚠️ สำคัญ:** slot ต้องไม่ซ้ำกัน ถ้าซ้ำ replica ตัวที่ start ทีหลังจะแย่ง slot ทำให้ replication ตัวเก่าหยุดทำงาน

---

## ตรวจสอบสถานะ

**บน primary** — ดู replica ทั้งหมดที่เชื่อมต่ออยู่:

```bash
docker exec -it postgres_primary psql -U postgres -c "
SELECT client_addr, application_name, state, sync_state,
       pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn) AS lag_bytes
FROM pg_stat_replication;"
```

**บน primary** — ดู slot ทั้งหมด (ต้องเป็น `active = t` ทุกตัว):

```bash
docker exec -it postgres_primary psql -U postgres -c "
SELECT slot_name, active, restart_lsn FROM pg_replication_slots;"
```

**บน replica** — ยืนยันว่าอยู่ใน recovery mode:

```bash
docker exec -it postgres_replica psql -U postgres -c "SELECT pg_is_in_recovery();"
```

ต้องได้ `t`

## ทดสอบ Replication

```bash
# บน primary — สร้าง table + insert
docker exec -it postgres_primary psql -U postgres -c \
  "CREATE TABLE test(id serial primary key, data text); INSERT INTO test(data) VALUES('hello');"

# บน replica — อ่านได้ทันที
docker exec -it postgres_replica psql -U postgres -c "SELECT * FROM test;"

# บน replica — เขียนไม่ได้ (read-only)
docker exec -it postgres_replica psql -U postgres -c "INSERT INTO test(data) VALUES('nope');"
# ERROR: cannot execute INSERT in a read-only transaction
```

## หยุดและล้างข้อมูล

```bash
# เครื่องเดียว
docker-compose down          # หยุด (volume ยังอยู่)
docker-compose down -v       # หยุด + ลบ volume ข้อมูลหายทั้งหมด

# แยกเครื่อง
docker-compose -f docker-compose-primary.yml down
docker-compose -f docker-compose-replica.yml down
```

---

## Troubleshooting

### Replica เชื่อมต่อ Primary ไม่ได้

```bash
# จาก replica
ping <primary-ip>
nc -zv <primary-ip> 5432

# บน primary — ดู log
docker logs postgres_primary --tail 50
```

ตรวจว่า `pg_hba.conf` มี rule สำหรับ IP ของ replica แล้ว

### Slot Overflow / Primary WAL เต็ม

ถ้า replica offline นาน primary จะเก็บ WAL ไว้เรื่อยๆ จนดิสก์เต็ม แก้:

```bash
docker exec -it postgres_primary psql -U postgres -c \
  "SELECT pg_drop_replication_slot('replica_slot_X');"
```

**หมายเหตุ:** drop แล้วต้อง re-bootstrap replica ตัวนั้นใหม่

### Authentication Failed

- ตรวจ `REPLICATION_PASSWORD` ตรงกันทั้ง primary และ replica
- ตรวจ `pg_hba.conf` ระบุ `replicator` ไม่ใช่ user อื่น

---

## License

MIT — ดู [LICENSE.md](LICENSE.md)
