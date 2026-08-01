# PostgreSQL 17 Cluster พร้อม Read Replica

![Docker](https://img.shields.io/badge/Docker-27.2.0-orange)
![Docker Compose](https://img.shields.io/badge/Docker%20Compose-v1.29.2--desktop.2-orange)
![PostgreSQL](https://img.shields.io/badge/PostgreSQL-17-green)

## ภาพรวม

Docker Compose ชุดนี้สร้าง PostgreSQL 17 cluster ที่มี primary (read-write) หนึ่งตัว และ read replica หนึ่งตัว เพื่อรองรับ high availability และกระจายโหลดการอ่านข้อมูล

**รูปแบบการติดตั้ง 2 แบบ:**

- **แบบเครื่องเดียว** (`docker-compose.yml`) - primary และ replica อยู่บนเครื่องเดียวกัน
- **แบบแยกเซิร์ฟเวอร์** (`docker-compose-primary.yml` + `docker-compose-replica.yml`) - primary และ replica อยู่คนละเครื่อง (physical/VM)

![Docker-compose Stack](docs/docker-compose-stack.png)

## คุณสมบัติ

### จุดเด่นของ PostgreSQL 17

PostgreSQL 17 มีการปรับปรุงที่สำคัญหลายอย่าง:

- **Logical Replication ที่ดีขึ้น**: ประสิทธิภาพและความเสถียรของ logical replication ดีขึ้น
- **Query Performance ที่เร็วขึ้น**: การวางแผนและประมวลผล query ถูก optimize
- **Partitioning ที่ดีขึ้น**: ความสามารถในการทำ table partitioning เพิ่มขึ้น
- **Security ที่แข็งแรงขึ้น**: มีฟีเจอร์ด้าน security ใหม่ๆ
- **Monitoring ที่ดีขึ้น**: เครื่องมือด้าน monitoring และ observability ดีขึ้น
- **Performance ที่ดีขึ้นทั้งระบบ**: มีการปรับปรุงประสิทธิภาพในหลายจุด

## ⚠️ ข้อควรระวังสำคัญ

> **setup นี้เป็น Proof of Concept (PoC) ห้ามใช้บน production**

setup นี้เหมาะสำหรับ:

- การเรียนรู้
- Development environment
- ทดสอบแนวคิดเรื่อง replication
- ทำความเข้าใจพื้นฐาน PostgreSQL replication

**สิ่งที่ต้องพิจารณาสำหรับ production:**

- ยังไม่มี security hardening
- ไม่มี backup strategy
- ไม่มี monitoring/alerting
- ไม่มี high availability นอกจาก replication พื้นฐาน
- ไม่มี disaster recovery
- ไม่มี network isolation
- ไม่มี SSL/TLS encryption
- ยังไม่ได้จัดการ user/role อย่างเหมาะสม
- ไม่มี logging/auditing

สำหรับ production ควร:

- ทำ security hardening
- ตั้ง monitoring/alerting
- ทำ backup และ recovery procedure
- ใช้ managed database service
- ปรึกษาผู้เชี่ยวชาญด้าน database
- ทำตาม PostgreSQL best practices

### คุณสมบัติของ Cluster

- Primary (Read-Write) และ Read Replica
- ตั้งค่า replication อัตโนมัติ
- Persistent data storage
- Health monitoring
- Network แยก (แบบเครื่องเดียว) หรือเชื่อมข้ามเครื่อง (แบบแยกเซิร์ฟเวอร์)

## สถาปัตยกรรม

### การทำงานของ Replication

setup นี้ใช้ physical replication ระหว่าง primary กับ replica:

1. Primary node (`postgres_primary`) รับ write operation
2. การเปลี่ยนแปลงถูกเขียนลง Write-Ahead Log (WAL)
3. Replica (`postgres_replica`) stream WAL เหล่านั้นต่อเนื่อง
4. Replica นำ WAL ไป apply เพื่อให้ข้อมูลตรงกับ primary
5. Replica ทำงานใน hot standby mode รับ read operation ได้

---

## เริ่มต้นแบบเครื่องเดียว

ใช้เมื่อ primary และ replica อยู่บนเครื่องเดียวกัน

### 1. Clone และตั้งค่า

```bash
git clone git@github.com:luismr/postgres-docker-compose-cluster.git
cd postgres-docker-compose-cluster
cp .env.example .env
```

### 2. เริ่ม Cluster

```bash
docker-compose up -d
```

### 3. ตรวจสอบ Service

```bash
docker-compose ps
```

**Port:**

- Primary: `localhost:5432`
- Replica: `localhost:5433`

---

## เริ่มต้นแบบแยกเซิร์ฟเวอร์ (คนละเครื่อง)

ใช้เมื่อ primary และ replica อยู่บน physical server หรือ VM คนละเครื่อง

### สิ่งที่ต้องมี

- Server 2 เครื่องที่ติดตั้ง Docker
- Network ที่เชื่อมถึงกันได้
- Firewall เปิด port 5432 จาก replica ไป primary

### เซิร์ฟเวอร์ 1 (Primary)

1. **Clone repository:**

```bash
git clone git@github.com:luismr/postgres-docker-compose-cluster.git
cd postgres-docker-compose-cluster
```

1. **สร้าง `.env`:**

```bash
cp .env.example .env
# แก้ค่าตามต้องการ (ค่า default: postgres/postgres/postgres)
```

1. **สร้าง `pg_hba.conf`** เพื่ออนุญาตให้ replica เชื่อมต่อ:

```bash
cat > pg_hba.conf << 'EOF'
# TYPE  DATABASE        USER            ADDRESS                 METHOD
local   all             all                                     trust
host    all             all             127.0.0.1/32            trust
host    all             all             ::1/128                 trust
host    all             all             0.0.0.0/0               md5
host    replication     replica         0.0.0.0/0               md5
EOF
```

**⚠️ หมายเหตุด้าน Security:** `0.0.0.0/0` เปิดให้ทุก IP บน production ควรเปลี่ยนเป็น IP ของ replica เท่านั้น:

```text
host    replication     replica         192.168.1.20/32         md5
```

1. **แก้ `docker-compose-primary.yml`** ให้ mount pg_hba.conf:

```yaml
volumes:
  - ./pg_hba.conf:/etc/postgresql/pg_hba.conf
  - ./initdb.d/00_init.sql:/docker-entrypoint-initdb.d/00_init.sql
  - postgres_primary_data:/var/lib/postgresql/data
```

1. **เริ่ม primary:**

```bash
docker-compose -f docker-compose-primary.yml up -d
```

1. **ดู IP ของเซิร์ฟเวอร์ primary:**

```bash
ip addr show  # Linux
ipconfig      # Windows
```

จด IP ที่ได้ (เช่น `192.168.1.10`)

### เซิร์ฟเวอร์ 2 (Replica)

1. **Clone repository:**

```bash
git clone git@github.com:luismr/postgres-docker-compose-cluster.git
cd postgres-docker-compose-cluster
```

1. **สร้าง `.env` โดยใส่ IP ของ primary:**

```bash
cat > .env << EOF
POSTGRES_USER=postgres
POSTGRES_PASSWORD=postgres
POSTGRES_DB=postgres
PRIMARY_HOST=192.168.1.10
EOF
```

เปลี่ยน `192.168.1.10` เป็น IP จริงของเซิร์ฟเวอร์ primary

1. **เริ่ม replica:**

```bash
docker-compose -f docker-compose-replica.yml up -d
```

1. **ตรวจสอบ log:**

```bash
docker-compose -f docker-compose-replica.yml logs -f postgres_replica
```

ให้ดูข้อความ:

- "Waiting for primary to be ready..."
- "Primary is ready, starting replica..."
- "Replication setup complete"

### ตรวจสอบ Replication แบบแยกเซิร์ฟเวอร์

**บนเซิร์ฟเวอร์ Primary:**

```bash
docker exec -it postgres_primary psql -U postgres -c "SELECT * FROM pg_stat_replication;"
```

ควรเห็น 1 row ที่แสดงการเชื่อมต่อของ replica

**บนเซิร์ฟเวอร์ Replica:**

```bash
docker exec -it postgres_replica psql -U postgres -c "SELECT pg_is_in_recovery();"
```

ต้องได้ผลลัพธ์ `t` (true)

---

## การใช้งาน

### ตรวจสอบสถานะ Replication

**แบบเครื่องเดียว:**

```bash
docker exec -it postgres_primary psql -U postgres -c "SELECT * FROM pg_stat_replication;"
docker exec -it postgres_replica psql -U postgres -c "SELECT pg_is_in_recovery();"
```

**แบบแยกเซิร์ฟเวอร์ (รันบนแต่ละเครื่อง):**

```bash
# บนเซิร์ฟเวอร์ primary
docker exec -it postgres_primary psql -U postgres -c "SELECT * FROM pg_stat_replication;"

# บนเซิร์ฟเวอร์ replica
docker exec -it postgres_replica psql -U postgres -c "SELECT pg_is_in_recovery();"
```

### ทดสอบ Replication

1. **สร้าง table บน primary:**

```bash
docker exec -it postgres_primary psql -U postgres -c "CREATE TABLE test (id SERIAL PRIMARY KEY, data TEXT);"
```

1. **Insert ข้อมูลบน primary:**

```bash
docker exec -it postgres_primary psql -U postgres -c "INSERT INTO test (data) VALUES ('test data');"
```

1. **ตรวจสอบบน replica:**

```bash
docker exec -it postgres_replica psql -U postgres -c "SELECT * FROM test;"
```

### หยุด Cluster

**แบบเครื่องเดียว:**

```bash
docker-compose down
docker-compose down -v  # ลบ volume ด้วย (ข้อมูลจะหายทั้งหมด)
```

**แบบแยกเซิร์ฟเวอร์:**

```bash
# บนเซิร์ฟเวอร์ primary
docker-compose -f docker-compose-primary.yml down

# บนเซิร์ฟเวอร์ replica
docker-compose -f docker-compose-replica.yml down
```

---

## แก้ปัญหา

### Replica เชื่อมต่อ Primary ไม่ได้

**ตรวจสอบ network:**

```bash
# จากเซิร์ฟเวอร์ replica
ping <primary-ip>
telnet <primary-ip> 5432
```

**ตรวจสอบ firewall:**

```bash
# บนเซิร์ฟเวอร์ primary (Linux)
sudo ufw allow 5432/tcp
sudo iptables -L -n | grep 5432
```

**ดู log Docker:**

```bash
docker-compose -f docker-compose-replica.yml logs postgres_replica
```

### Replication ล่าช้า (Lag)

**ตรวจสอบ lag บน primary:**

```bash
docker exec -it postgres_primary psql -U postgres -c "
SELECT
  client_addr,
  state,
  sent_lsn,
  write_lsn,
  flush_lsn,
  replay_lsn,
  sync_state
FROM pg_stat_replication;
"
```

### Authentication Failed

**ตรวจสอบว่า password ใน `.env` ทั้งสองเครื่องตรงกัน**

**ตรวจสอบว่า pg_hba.conf อนุญาต IP ของ replica แล้ว:**

```bash
docker exec -it postgres_primary cat /var/lib/postgresql/data/pg_hba.conf
```

---

## โครงสร้างไฟล์

```text
.
├── docker-compose.yml              # setup แบบเครื่องเดียว
├── docker-compose-primary.yml      # เซิร์ฟเวอร์ primary (แบบแยก)
├── docker-compose-replica.yml      # เซิร์ฟเวอร์ replica (แบบแยก)
├── .env.example                    # template สำหรับ environment
├── initdb.d/
│   └── 00_init.sql                 # สร้าง role และ slot สำหรับ replication
├── pg_hba.conf                     # (ต้องสร้างเองสำหรับ primary แบบแยก)
└── README.md
```

---

## Contributing

ยินดีรับ contribution วิธีร่วม:

1. Fork repository
2. สร้าง feature branch (`git checkout -b feature/amazing-feature`)
3. Commit การเปลี่ยนแปลง (`git commit -m 'Add some amazing feature'`)
4. Push ไปยัง branch (`git push origin feature/amazing-feature`)
5. เปิด Pull Request

## License

โปรเจกต์นี้ใช้ MIT License ดูรายละเอียดที่ [LICENSE.md](LICENSE.md)
