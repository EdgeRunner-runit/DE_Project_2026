# BookMyShow Database Architecture & Engineering Overview

**Course:** Database Management Systems (B.Tech 2nd Year)  
**Team:** T0132 · **Section:** E and D  
**Lead:** Piyush Alagh · **Engineers:** Kushal Garg, Aujasya Rajput, Aryan Damara  
**Platform Target:** PostgreSQL 16+ on Apple M4 / Ubuntu Enterprise  

---

## 1. System Architecture & Topology

The BookMyShow Ticketing Engine is engineered to handle millions of seat reservations with strict concurrency guarantees, zero double-booking, and sub-millisecond response times.

```mermaid
flowchart TD
    subgraph Clients ["Client & Microservice Layer"]
        App["Mobile / Web Frontend"]
        PayGW["Payment Webhook Callback"]
        ExpiryDaemon["Seat-Lock Expiry Daemon (10m TTL)"]
    end

    subgraph Pooler ["Connection Management"]
        PgBouncer["PgBouncer Pooler (Transaction Mode, 5000 max_conn)"]
    end

    subgraph PrimaryDB ["PostgreSQL 16 Primary (Read/Write)"]
        bms_schema["Schema 'bms'"]
        shows_table["shows (GiST exclusion: no show overlaps)"]
        bookings_table["bookings (150k seed -> 3M large)"]
        seats_table["booking_seats (PK show_id, seat_id: atomic locks)"]
    end

    subgraph AnalyticalReplica ["Read Replica (Asynchronous Streaming)"]
        BI["Analytics, Box Office & Finance Dashboards"]
        MVs["Materialized Views (Concurrent Refresh)"]
    end

    App --> PgBouncer
    PayGW --> PgBouncer
    ExpiryDaemon --> PgBouncer
    PgBouncer --> PrimaryDB
    PrimaryDB -.->|"Streaming Replication"| AnalyticalReplica
    BI --> AnalyticalReplica
```

---

## 2. Transaction Lifecycle & Seat Locking State Machine

```mermaid
stateDiagram-v2
    [*] --> PENDING: User Initiates Checkout (W01)<br/>Lock Seats for 10 min (W02)
    PENDING --> CONFIRMED: Payment Success Callback (W03)<br/>Update status = CONFIRMED
    PENDING --> CANCELLED: User Cancels or Leaves Page
    PENDING --> EXPIRED: 10-Minute Hold Window Expires (W04)<br/>Daemon Deletes booking_seats
    CANCELLED --> [*]: Physical Seats Freed Immediately
    EXPIRED --> [*]: Physical Seats Available for Re-booking
    CONFIRMED --> [*]: Final Settlement
```

### Concurrency Protection Rules:
1. **Atomic Lock Exclusivity:** `PRIMARY KEY (show_id, seat_id)` on `booking_seats` ensures two transactions can NEVER hold the same seat for a show. If a collision occurs, PostgreSQL immediately rejects the second transaction with a unique violation.
2. **Non-Blocking Checkout:** Workload query `W02` uses `ON CONFLICT (show_id, seat_id) DO NOTHING`, ensuring graceful degradation without application crashes.
3. **Show Overlap Prevention:** `EXCLUDE USING gist (screen_id WITH =, tstzrange(starts_at, ends_at) WITH &&)` physically guarantees that no screen can be scheduled with overlapping showtimes.

---

## 3. Four-Layer Optimization Framework

| Layer | Implementation Artifact | Key Impact |
|---|---|---|
| **Layer 1: Relational Schema & Types** | [`sql/01_schema.sql`](../sql/01_schema.sql) | Sized integer types (`SMALLINT` for durations/ratings), exact currency precision (`NUMERIC(10,2)`), 16+ business domain CHECK constraints, temporal exclusion constraint. |
| **Layer 2: Production Indexing** | [`sql/05_indexes.sql`](../sql/05_indexes.sql) | Composite indexes, covering indexes with `INCLUDE`, partial indexes (`WHERE status = 'PENDING'`), and GIN trigram text search. |
| **Layer 3: Query Rewrites** | [`sql/06_optimized_queries.sql`](../sql/06_optimized_queries.sql) | Sargable date range predicates, antijoins fixing SQL Three-Valued Logic (`NOT EXISTS`), and $O(1)$ Keyset Pagination replacing $O(N)$ `OFFSET`. |
| **Layer 4: Partitioning & Scaling** | [`sql/08_partitioning.sql`](../sql/08_partitioning.sql) | Monthly RANGE partitioning on `shows` and `bookings`, HASH partitioning on `booking_seats`, partition pruning, and materialized views. |

---

## 4. Documentation & Artifact Navigation Index

| Milestone | Deliverable Document | Core Artifacts & Scripts |
|---|---|---|
| **CP1: Problem Understanding & Schema** | [`docs/01_problem_understanding.md`](01_problem_understanding.md)<br>[`docs/02_schema_design.md`](02_schema_design.md) | [`sql/01_schema.sql`](../sql/01_schema.sql)<br>[`sql/02_load_data.sql`](../sql/02_load_data.sql)<br>[`diagrams/er_diagram.svg`](../diagrams/er_diagram.svg) |
| **CP2: Baseline Benchmarks** | [`docs/03_baseline_timings.md`](03_baseline_timings.md) | [`benchmarks/results/baseline/summary.csv`](../benchmarks/results/baseline/summary.csv)<br>[`benchmarks/run_benchmark.sh`](../benchmarks/run_benchmark.sh) |
| **CP3: Code Optimization** | [`docs/04_optimization_report.md`](04_optimization_report.md) | [`sql/05_indexes.sql`](../sql/05_indexes.sql)<br>[`sql/06_optimized_queries.sql`](../sql/06_optimized_queries.sql)<br>[`benchmarks/results/optimized/summary.csv`](../benchmarks/results/optimized/summary.csv) |
| **CP4: Scalability & Partitioning** | [`docs/05_scalability_report.md`](05_scalability_report.md) | [`sql/08_partitioning.sql`](../sql/08_partitioning.sql)<br>[`benchmarks/results/large/summary.csv`](../benchmarks/results/large/summary.csv) |
| **CP5: Individual Viva Defense** | [`docs/06_individual_analysis_prep.md`](06_individual_analysis_prep.md) | Complete oral examination prep card, cost analysis, and plan walkthroughs. |
| **Production Runbooks** | [`docs/runbooks/`](runbooks/) | Disaster Recovery, Zero-Downtime Deployments, and DBA diagnostics. |
