# BookMyShow Production Runbook: Zero-Downtime Deployment & Migration

**Scope:** Schema Evolution, Zero-Downtime Index Builds, Partition Swapping  
**Service Availability Target:** 99.99% Availability (Max 4.38 mins downtime/month)  
**Authors:** Team T0132  

---

## 1. Zero-Downtime Index Deployment Pattern

In standard PostgreSQL, executing `CREATE INDEX` acquires a `SHARE` lock on the table. This permits concurrent `SELECT` queries, but **completely blocks all concurrent INSERT, UPDATE, and DELETE operations**. On a high-traffic table like `bookings` or `booking_seats`, a 30-second index build would cause connection pool exhaustion and checkout failures.

### The Standard Solution: `CREATE INDEX CONCURRENTLY`
PostgreSQL `CONCURRENTLY` builds the index in two passes without acquiring table locks:

```sql
-- Safe production index build
SET search_path TO bms;
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_bookings_customer_id 
ON bookings (customer_id);
```

### Safety Checklist for Concurrent Indexing:
1. Cannot run inside a `BEGIN ... COMMIT` transaction block.
2. If interrupted or terminated, leaves an `INVALID` index. Always inspect:
   ```sql
   SELECT indexrelid::regclass, indisvalid 
   FROM pg_index 
   WHERE indisvalid = false;
   -- If invalid, drop and re-run:
   DROP INDEX CONCURRENTLY IF EXISTS bms.idx_name_here;
   ```

---

## 2. Zero-Downtime Partition Migration Pattern

Migrating an existing 3-million-row unpartitioned `bookings` table to a partitioned table (`bookings_partitioned`) in production:

### Phase 1: Shadow Table Creation
Create `bookings_partitioned` and partition tables ahead of time.

### Phase 2: Dual-Writing Trigger
Install a lightweight trigger on the old `bookings` table that replicates real-time writes into `bookings_partitioned`:

```sql
CREATE OR REPLACE FUNCTION bms.sync_booking_to_partitioned()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO bms.bookings_partitioned VALUES (NEW.*)
    ON CONFLICT (booking_id, booked_at) DO UPDATE 
    SET status = EXCLUDED.status, total_amount = EXCLUDED.total_amount;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_sync_bookings
AFTER INSERT OR UPDATE ON bms.bookings
FOR EACH ROW EXECUTE FUNCTION bms.sync_booking_to_partitioned();
```

### Phase 3: Background Backfill of Historical Rows
Backfill historical data in idempotent batches during off-peak hours:

```sql
INSERT INTO bms.bookings_partitioned
SELECT * FROM bms.bookings
WHERE booked_at < '2026-06-01'
ON CONFLICT (booking_id, booked_at) DO NOTHING;
```

### Phase 4: Atomic Table Swap
In a sub-millisecond DDL transaction:

```sql
BEGIN;
LOCK TABLE bms.bookings IN ACCESS EXCLUSIVE MODE;
DROP TRIGGER trg_sync_bookings ON bms.bookings;

ALTER TABLE bms.bookings RENAME TO bookings_old;
ALTER TABLE bms.bookings_partitioned RENAME TO bookings;
COMMIT;
```

---

## 3. Post-Deployment Verification & Smoke Testing

Immediately after deploying DDL or indexes:
1. Verify index usage in `pg_stat_user_indexes`.
2. Run integrity check suite:
   ```bash
   psql -d bms -f tests/test_integrity.sql
   ```
3. Check application error rates and APM p99 database response times.
