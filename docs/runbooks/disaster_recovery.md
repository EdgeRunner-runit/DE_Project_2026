# BookMyShow Production Runbook: Disaster Recovery & Backup Strategy

**Target Architecture:** PostgreSQL 16+ Production Cluster  
**Service Tier:** Tier 1 Mission-Critical (Ticketing & Financial Ledger)  
**Recovery Objectives:** RPO (Recovery Point Objective) $\le$ 5 minutes · RTO (Recovery Time Objective) $\le$ 15 minutes  
**Authors:** Team T0132  

---

## 1. Backup Architecture Overview

To protect against catastrophic hardware failure, accidental drops, and database corruption, BookMyShow employs a dual-tiered backup topology:

1. **Continuous Write-Ahead Log (WAL) Archiving:** Streams incremental transaction deltas to high-durability cloud object storage (S3/GCS) every 60 seconds.
2. **Weekly Physical Base Backups (`pg_basebackup`):** Captures full binary filesystem snapshots of the PostgreSQL data directory with zero application downtime.
3. **Daily Parallel Logical Backups (`pg_dump`):** Captures directory-format snapshots partitioned across 4 threads for granular table-level and schema recovery.

---

## 2. Continuous WAL Archiving Setup

In `postgresql.conf`:

```ini
wal_level = replica
archive_mode = on
archive_command = 'gzip -c %p > /mnt/bms_wal_archive/%f.gz'
archive_timeout = 300   # Force archive rotation every 5 minutes if traffic is quiet
```

---

## 3. Physical Base Backup Execution

Physical backups capture the live database cluster without read locks:

```bash
#!/usr/bin/env bash
# Trigger daily physical base backup
BACKUP_DIR="/mnt/backups/physical/$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

pg_basebackup \
  -h 127.0.0.1 \
  -p 5432 \
  -U replicator \
  -D "$BACKUP_DIR" \
  -Fp \
  -Xs \
  -P \
  -v \
  --checkpoint=fast

echo "[+] Base backup completed to $BACKUP_DIR"
```

---

## 4. Point-in-Time Recovery (PITR) Procedure

If a destructive operational error occurs (e.g. accidental `TRUNCATE bookings` at `2026-06-25 14:32:00 IST`):

### Step 1: Halt Database Service
```bash
sudo systemctl stop postgresql
```

### Step 2: Preserve Current Corrupted WAL Logs
```bash
mv /var/lib/postgresql/16/main/pg_wal /mnt/wal_recovery_stash
```

### Step 3: Restore Nearest Base Backup
```bash
rm -rf /var/lib/postgresql/16/main/*
tar -xzf /mnt/backups/physical/20260625_000000.tar.gz -C /var/lib/postgresql/16/main/
```

### Step 4: Configure Recovery Target
In `/var/lib/postgresql/16/main/postgresql.auto.conf` or `recovery.signal`:

```ini
restore_command = 'gunzip -c /mnt/bms_wal_archive/%f.gz > %p'
recovery_target_time = '2026-06-25 14:31:30+05:30'  # 30 seconds prior to disaster
recovery_target_action = 'promote'
```

### Step 5: Start Service & Verify
```bash
touch /var/lib/postgresql/16/main/recovery.signal
sudo systemctl start postgresql

# Monitor recovery progress in log
tail -f /var/log/postgresql/postgresql-16-main.log
# Look for: "recovery stopping at restore point ... archive recovery complete"
```

---

## 5. Parallel Logical Backup Procedure (`pg_dump`)

Used for environment replication, test database seeding, and auditing:

```bash
# 4-thread parallel logical dump in custom directory format
pg_dump \
  -h localhost \
  -U postgres \
  -d bms \
  -Fd \
  -j 4 \
  -f /mnt/backups/logical/bms_dump_$(date +%Y%m%d) \
  -v

# Fast parallel restore:
# pg_restore -h localhost -U postgres -d bms_test -j 4 /mnt/backups/logical/bms_dump_20260625/
```
