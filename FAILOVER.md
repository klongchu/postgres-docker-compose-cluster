# คู่มือกู้ระบบเมื่อ Primary พัง (Manual Failover)

> Cluster นี้ทำแค่ physical streaming replication ไม่มี automatic failover
> ดู [PRODUCTION.md](PRODUCTION.md#12-failover) หัวข้อ Failover ประกอบ

## 1. ยืนยันว่า Primary พังจริง

**ห้าม promote replica ถ้า primary ยังมีชีวิตอยู่** ไม่ว่ากรณีใด — จะเกิด split-brain
(สอง instance รับ write พร้อมกัน ทำให้ข้อมูลขัดแย้งกันและกู้คืนยาก)

```bash
# รันจากเครื่อง primary หรือเครื่องที่เข้าถึง network เดียวกัน
docker exec postgres_primary pg_isready -U postgres

# ดูสถานะ replication ก่อนพังล่าสุด (รันจากที่ยังเข้า primary ได้ หรือดู log ที่ผ่านมา)
bash scripts/health-check.sh
```

ถ้าเป็นแค่ network partition ชั่วคราว ให้แก้ network ก่อน ไม่ต้อง failover

## 2. เลือก Replica ที่ Lag น้อยที่สุด

ถ้ามีหลาย replica ให้เทียบ `lag_bytes` / `lag_seconds` จาก `scripts/health-check.sh`
รอบล่าสุดที่เก็บได้ (เช่นจาก monitoring/log) แล้วเลือกตัวที่ข้อมูลใหม่สุด

## 3. Promote Replica ที่เลือก

```bash
docker exec postgres_replica pg_ctl promote -D /var/lib/postgresql/data
```

ยืนยันว่า promote สำเร็จ (ต้องได้ `f` แปลว่าออกจาก recovery mode แล้ว):

```bash
docker exec postgres_replica psql -U postgres -c "SELECT pg_is_in_recovery();"
```

## 4. ชี้ Application ไปที่ Primary ตัวใหม่

`pg_ctl promote` ไม่ redirect traffic ให้อัตโนมัติ ต้องทำเอง:

- แก้ host ปลายทางใน [docker-compose-pgbouncer.prod.yml](docker-compose-pgbouncer.prod.yml) ให้ชี้ไปที่ replica ที่ promote แล้ว restart PgBouncer
- หรือถ้า app ต่อตรง ให้แก้ connection string / DNS ที่ใช้อยู่

## 5. Repoint Replica ตัวอื่นที่เหลือ

Replica อื่นยัง stream จาก primary เก่าที่ตายอยู่ (ผูกไว้ใน `primary_conninfo`
ตอน bootstrap — ดู [replica-entrypoint.prod.sh:41](replica/replica-entrypoint.prod.sh#L41))
ต้อง rebuild ให้ชี้มา primary ใหม่:

```bash
docker compose -f docker-compose-replica.prod.yml down -v
# แก้ .env: PRIMARY_HOST=<IP ของ primary ใหม่>
docker compose -f docker-compose-replica.prod.yml up -d
```

## 6. Rebuild Primary เก่า

**ห้าม start primary เก่าขึ้นมาตรงๆ** จะกลายเป็นตัวที่สองที่คิดว่าตัวเองเป็น primary
ต้องล้างข้อมูลเก่าแล้ว bootstrap ใหม่ในฐานะ replica ของ primary ตัวใหม่:

```bash
docker compose -f docker-compose-primary.prod.yml down -v
# แก้ .env บนเครื่องนี้: PRIMARY_HOST=<IP ของ primary ใหม่>
#   REPLICA_SLOT / REPLICA_NAME ต้องไม่ซ้ำกับ replica ตัวอื่นที่มีอยู่
docker compose -f docker-compose-replica.prod.yml up -d
```

`down -v` ลบ volume ข้อมูลเก่าทิ้งจริง — ใช้เมื่อยืนยันแล้วว่าจะให้เครื่องนี้เป็น replica ต่อไป

## ⚠️ Data Loss ที่ต้องรู้

[primary/postgresql.prod.conf](primary/postgresql.prod.conf) ตั้ง `synchronous_commit = on`
แต่ **ไม่ได้ตั้ง `synchronous_standby_names`** — replication จึงเป็นแบบ async จริง

ผลคือ transaction ที่ primary ยืนยัน commit แล้วแต่ WAL ยังไม่ถึง replica **จะหายไปตอน failover**
ปริมาณที่หาย ≈ `lag_bytes` ของ replica ที่เลือก promote ณ วินาทีที่ primary พัง

ถ้าต้องการ zero data loss ต้องตั้ง `synchronous_standby_names` (เช่น `'FIRST 1 (replica_1, replica_2)')`
แต่แลกกับ write latency ที่สูงขึ้น เพราะ primary ต้องรอ replica ตัวใดตัวหนึ่ง ACK ก่อน commit

## สำหรับ Production จริงจัง

ขั้นตอนนี้เป็น manual ทั้งหมด เหมาะกับ downtime ระดับนาที ถ้าต้องการ automatic failover
ให้ใช้ **Patroni + etcd/Consul**, **CloudNativePG** บน Kubernetes, หรือ managed PostgreSQL
(ดู [PRODUCTION.md:243](PRODUCTION.md#L243))
