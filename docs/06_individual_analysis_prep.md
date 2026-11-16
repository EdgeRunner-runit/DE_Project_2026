# Phase 6 / CP5: Individual Analysis & Viva Oral Defense Manual

**Course:** Database Management Systems (B.Tech 2nd Year)  
**Checkpoint:** CP5 — Individual Analysis & Oral Defense (40 Marks)  
**Author:** Kushal Garg (`kshlgrg`) · **Team:** T0132  
**Role:** Senior Database Architect / Performance Engineer  

---

## 1. Executive Guide: How CP5 is Evaluated

CP5 accounts for **40 out of the 100 total course marks** (50% of the DE component). Evaluation is conducted individually in class through direct oral questioning and code inspection by the faculty. 

The evaluation tests three dimensions:
1. **Mechanical Understanding of PostgreSQL Engine:** Reading `EXPLAIN (ANALYZE, BUFFERS)` output, interpreting buffer hits vs disk reads, cost calculations, scan nodes, and join strategies.
2. **Indexing & Query Rewrite Mastery:** Explaining *why* specific indexes and rewrites were chosen, how sargability was restored, and how Three-Valued Logic bugs were fixed.
3. **Scalability & Concurrency Trade-offs:** Defending partitioning keys, concurrency locks (`PRIMARY KEY (show_id, seat_id)`), and GiST temporal exclusion constraints.

---

## 2. PostgreSQL Query Engine Internals: Core Concepts

### 2.1 Anatomy of `EXPLAIN (ANALYZE, BUFFERS)`
When faculty asks: *"Walk me through the execution plan of this query"*, refer to these exact mechanics:

```text
Bitmap Heap Scan on shows (cost=4.82..124.50 rows=48 width=64) (actual time=0.082..0.169 rows=48 loops=1)
  Buffers: shared hit=14 read=0 dirtied=0
  -> Bitmap Index Scan on idx_shows_movie_starts (cost=0.00..4.81 rows=48) (actual time=0.024..0.024 rows=48 loops=1)
       Index Cond: ((movie_id = 2) AND (starts_at >= '2026-07-02'::timestamptz))
Planning Time: 0.115 ms
Execution Time: 0.169 ms
```

1. **`cost=4.82..124.50`:**
   - **Startup Cost (`4.82`):** Estimated work required before the first row can be returned (e.g. building the in-memory bitmap or sorting).
   - **Total Cost (`124.50`):** Estimated work to complete the entire node, measured in arbitrary disk page fetch cost units (where 1 sequential page fetch $= 1.0$, random fetch $= 4.0$).
2. **`actual time=0.082..0.169`:**
   - Time in milliseconds to return the first tuple and final tuple of this node.
3. **`loops=1`:**
   - Number of times this node was executed (critical in nested loops: total time is `actual time × loops`).
4. **Buffer Metrics (`shared hit=14 read=0`):**
   - **`shared hit`:** 8KB data/index pages found already cached in PostgreSQL `shared_buffers` in RAM (zero disk I/O).
   - **`shared read`:** Pages not in memory, requiring an OS/disk read.
   - **`shared dirtied`:** Pages modified in memory during write operations.

---

### 2.2 The Four PostgreSQL Scan Types: When and Why

| Scan Type | How it Works | When PostgreSQL Selects It | Example in BMS |
|---|---|---|---|
| **Sequential Scan (`Seq Scan`)** | Reads every 8KB heap block of the table sequentially from beginning to end. | High selectivity (query needs > 15–20% of table rows), or small table (< 100 blocks). | Catalog queries on `movies` (300 rows) or full-table analytics (`R15`). |
| **Index Scan** | Traverses B-tree root $\rightarrow$ branch $\rightarrow$ leaf to find row TID, then fetches the tuple directly from table heap. | Low selectivity (< 5% of rows) when returning few rows with specific columns. | Primary key lookups (`R04`, `R23`) or foreign key lookups (`R05`). |
| **Index Only Scan** | Traverses B-tree leaf pages and satisfies query *entirely* from index attributes without touching table heap. | All projected and filtered columns exist in the index, AND table pages are marked clean in the Visibility Map. | `R20` via `idx_bookings_confirmed_covering(booked_at, total_amount)` or `R03` on `booking_seats`. |
| **Bitmap Index + Heap Scan** | Phase 1: Index scan builds a bitmap of matching physical block IDs. Phase 2: Heap scan reads matching pages in physical sequential order. | Multiple index conditions combined with `AND`/`OR`, or medium selectivity (prevents random disk head thrashing). | `R02` filtering on `(movie_id, starts_at)` or `R17`. |

---

### 2.3 The Three Join Algorithms

1. **Nested Loop Join:**
   - Outer loop iterates through driving table; for each row, inner loop performs an index lookup.
   - *Best for:* Small outer set joined to indexed inner table (`R03`, `R07`).
2. **Hash Join:**
   - Hashes entire inner table into memory bucket hash table; scans outer table and probes hash table.
   - *Best for:* Large unindexed sets or broad aggregations (`R11`, `R12`, `R18`).
3. **Merge Join:**
   - Both tables pre-sorted on join key; scans both synchronously like a zipper merge.
   - *Best for:* Large sets already sorted by indexes.

---

## 3. High-Impact Oral Defense Questions & Model Answers

### Question 1: "Why did Query R13 ('Offers never redeemed') return 0 rows in baseline, and what was the root cause?"
* **Model Answer:**
  > "The original query used a subquery with `NOT IN`:  
  > `WHERE offer_code NOT IN (SELECT offer_code FROM bookings)`.  
  > In the `bookings` table, 85% of checkout transactions have `offer_code IS NULL` because customers checkout without a promo coupon. Under standard SQL Three-Valued Logic (`TRUE`, `FALSE`, `UNKNOWN`), comparing any value to `NULL` yields `UNKNOWN`.  
  > In SQL, `val NOT IN (val1, NULL)` evaluates to `NOT (val = val1 OR val = NULL)` $\rightarrow$ `NOT (FALSE OR UNKNOWN)` $\rightarrow$ `NOT (UNKNOWN)` $\rightarrow$ `UNKNOWN`.  
  > Because the `WHERE` clause accepts only rows that evaluate to `TRUE`, the entire condition evaluates to `UNKNOWN` for every single offer, resulting in an empty set (0 rows).  
  > **Fix:** We rewrote the query using an antijoin:  
  > `WHERE NOT EXISTS (SELECT 1 FROM bookings b WHERE b.offer_code = o.offer_code)`.  
  > `NOT EXISTS` tests for row presence and handles `NULL` values correctly, restoring the 7 legitimate unredeemed offers."

---

### Question 2: "Why is `PRIMARY KEY (show_id, seat_id)` used on `booking_seats` rather than a surrogate auto-increment ID?"
* **Model Answer:**
  > "Using a surrogate integer key like `booking_seat_id INT PRIMARY KEY` would create a severe concurrency vulnerability: the database engine would not inherently prevent two concurrent transactions from inserting identical `(show_id, seat_id)` rows for the same show without an auxiliary unique index.  
  > By establishing `PRIMARY KEY (show_id, seat_id)` directly on the table:
  > 1. **Engine-Level Concurrency Protection:** PostgreSQL enforces atomic row exclusivity at the storage layer via the primary B-tree. If two users attempt to lock the same seat simultaneously, the second transaction is immediately blocked or aborted by unique violation.
  > 2. **Native Support for Upsert / On Conflict:** Workload query `W02` uses `ON CONFLICT (show_id, seat_id) DO NOTHING`. This requires a unique or primary key constraint on `(show_id, seat_id)` as the conflict target.
  > 3. **Declarative Partitioning Rule:** When we partition `booking_seats` by HASH on `show_id`, PostgreSQL requires the partition key to be part of the primary key. Since `show_id` is already in the PK, zero schema redesign was required."

---

### Question 3: "Why can't a simple CHECK constraint prevent overlapping shows on the same screen, and how does `btree_gist` solve it?"
* **Model Answer:**
  > "Relational `CHECK` constraints in standard SQL are strictly **row-local**: they can only evaluate expressions on columns within the single tuple being inserted or updated. They cannot evaluate relationships across multiple rows in the same table.  
  > Preventing two shows from overlapping on the same screen requires comparing the prospective show's time range against all existing rows for that `screen_id`.  
  > We solved this by loading the `btree_gist` extension and defining an **Exclusion Constraint**:  
  > `EXCLUDE USING gist (screen_id WITH =, tstzrange(starts_at, ends_at) WITH &&)`.  
  > PostgreSQL uses a Generalized Search Tree (GiST) to index temporal ranges (`tstzrange`). The operator `&&` checks for range intersection, and `=` checks for matching screens. The engine enforces temporal disjointness in $O(\log N)$ time, physically preventing auditorium double-booking."

---

### Question 4: "Why did you replace `OFFSET` pagination in Query R22 with Keyset Pagination?"
* **Model Answer:**
  > "`OFFSET N LIMIT K` has an algorithmic complexity of $O(N)$. PostgreSQL must traverse the index, locate all $N$ tuples, read them, and discard them before returning the subsequent $K$ rows.  
  > On our 20× large dataset (3 million bookings), fetching deep pages (e.g. `OFFSET 100000`) caused query latency to balloon from 5 ms to over 85 ms, consuming thousands of buffer page reads.  
  > We replaced it with **Keyset Pagination (Seek Method)**:  
  > `WHERE (booked_at, booking_id) < ($last_booked_at, $last_booking_id) ORDER BY booked_at DESC, booking_id DESC LIMIT 20`.  
  > Backed by our composite index `idx_bookings_booked_at_desc(booked_at DESC, booking_id DESC)`, PostgreSQL seeks directly to the first tuple after the cursor and reads exactly 20 index rows in $O(1)$ constant time (**0.088 ms**), completely eliminating dataset depth degradation."

---

### Question 5: "Explain how Query R20 achieves sub-10ms performance using an Index-Only Scan and the Visibility Map."
* **Model Answer:**
  > "Query R20 computes daily running revenue totals for June 2026 for confirmed bookings.  
  > Instead of scanning the table heap (150k rows on seed, 3M on large), we created a partial covering index:  
  > `CREATE INDEX idx_bookings_confirmed_covering ON bookings (booked_at, total_amount) WHERE status = 'CONFIRMED'`.  
  > This provides two performance multipliers:
  > 1. **Index-Only Scan:** Both `booked_at` (used for filtering and grouping) and `total_amount` (used for summation) exist directly within the index leaf pages. PostgreSQL never fetches table heap pages.
  > 2. **Visibility Map Verification:** PostgreSQL checks the table's Visibility Map. If all tuples on an 8KB page are known to be visible to all current transactions, PostgreSQL skips heap visibility checks entirely, satisfying the query purely from index buffer hits in memory."

---

### Question 6: "What happens when `work_mem` is exceeded during large sorting or hashing operations?"
* **Model Answer:**
  > "PostgreSQL allocates `work_mem` (default 4MB) per sort/hash operation within a query.  
  > If the data being sorted (e.g. in queries R14, R15, R21 with 3 million rows) exceeds `work_mem`, the query planner cannot complete the sort in RAM using `quicksort`. Instead, it spills intermediate sort runs to temporary disk files, executing an `external merge` sort.  
  > Disk I/O introduces severe latency spikes. In `EXPLAIN (ANALYZE, BUFFERS)`, this is visible as:  
  > `Sort Method: external merge  Disk: 28416kB`.  
  > We mitigated this by sizing `work_mem` to 64MB for analytical sessions and utilizing covering indexes that keep pre-sorted order."

---

## 4. Query-by-Query Reference Card (All 30 Queries)

| Query | What it Does | Baseline Scan | Optimized Scan & Index | Viva Defense Talking Point |
|:---:|---|---|---|---|
| **R01** | Movies in Bengaluru on 2026-07-02 | Seq Scan on shows | Bitmap Index Scan on `idx_shows_starts_at` | Replaced non-sargable `DATE(s.starts_at)` with range `[start, end)`. |
| **R02** | Showtimes for Movie 2 in Bengaluru | Seq Scan on shows | Bitmap Index Scan on `idx_shows_movie_starts(movie_id, starts_at)` | Composite index eliminates filtering 99% of scheduled shows. |
| **R03** | Seat layout & sold status for show 144446 | PK Scan on shows | Index Only Scan on `booking_seats_pkey(show_id, seat_id)` | Screen capacity is constant; zero scale degradation. |
| **R04** | Booking lookup by alphanumeric code | Unique Index Scan | Unique Index Scan on `bookings(booking_code)` | $O(\log N)$ point lookup; 0.048 ms on 3M rows. |
| **R05** | Customer's booking history | Seq Scan on bookings | Bitmap Index Scan on `idx_bookings_customer_id` | Foreign key indexing turns 150k row scan into 5-row index seek. |
| **R06** | Movie search by title substring | Seq Scan on movies | Trigram GIN Index `idx_movies_title_trgm` | `pg_trgm` GIN handles `ILIKE '%war%'` in $O(\log N)$ time. |
| **R07** | Venue occupancy on date | Seq Scan on shows | Index Scan on `idx_shows_starts_at` + `idx_screens_venue_id` | Joins only target venue's screens for that single day. |
| **R08** | Distributor box office for movie 1 | Seq Scan on bookings | Parallel Hash Join + `idx_shows_movie_starts` | Aggregates all shows of movie 1; scales with movie run. |
| **R09** | Stale pending bookings queue | Seq Scan on bookings | Index Scan on partial `idx_bookings_pending_id` | Partial index `WHERE status = 'PENDING'` indexes < 100 rows. |
| **R10** | Cinema cleaning gap check (< 20 min) | Nested Loop Scan | Composite `idx_shows_screen_starts_ends` + 4-hour bound | Self-join bounded by 4-hour window prevents $O(N^2)$ explosion. |
| **R11** | Revenue by seat class and screen type | Seq Scan on booking_seats | Parallel Seq Scan + Covering `idx_seats_covering` | Parallel workers aggregate 6M booking seats in < 1 second. |
| **R12** | Top 10 cinemas by June revenue | Seq Scan on bookings | Parallel Hash Aggregate with `work_mem` | Evaluates June shows via date index range. |
| **R13** | Offers never redeemed | Seq Scan (0 rows) | Antijoin `NOT EXISTS` against `bookings` | Fixed SQL Three-Valued Logic `NOT IN (NULL)` trap. |
| **R14** | Rating distribution per movie | Seq Scan on reviews | Hash Aggregate on `idx_movie_reviews_movie_id` | Groups 650k reviews in memory using 64MB `work_mem`. |
| **R15** | Hourly and day-of-week heatmap | Seq Scan on bookings | Parallel Hash Aggregate | Analyzes 3M bookings across 168 time buckets. |
| **R16** | Regional language collections in May | Seq Scan on bookings | Index range on May bookings | Pushes down language filter to catalog table. |
| **R17** | Unsold seats in a show | Seq Scan on seats | Index Only Scan on `booking_seats_pkey` | Antijoin on physical seat layout minus booked seats. |
| **R18** | Cancellation rate by cinema chain | Seq Scan on bookings | Parallel Hash Aggregate | Partial index on confirmed vs cancelled bookings. |
| **R19** | Distributor per-show ticket counts | Correlated subquery | Rewritten `LEFT JOIN ... GROUP BY` | Eliminated correlated subquery per show (2,359× speedup). |
| **R20** | June daily cumulative running revenue | Window Seq Scan | Index Only Scan on `idx_bookings_confirmed_covering` | Visibility Map allows scan without touching table heap. |
| **R21** | Top 100 loyal customers | Seq Scan on bookings | Parallel Hash Aggregate with in-memory sort | In-memory quicksort prevents disk spill. |
| **R22** | Paginated customer orders | OFFSET 10000 | Keyset Pagination `WHERE (booked_at, id) < ...` | Keyset pagination reduces deep pagination from 85 ms to 0.088 ms. |
| **R23** | Sign-in lookup by customer phone | Unique Index Scan | Unique B-tree Index Scan on `customers(phone)` | 0.028 ms point authentication. |
| **R24** | Average price by city and seat class | Multi-table Seq Scan | Parallel Hash Join with covering index | Pre-aggregated seats and screens before joining booking_seats. |
| **R25** | Late-night show occupancy (> 22:30) | Time-cast Seq Scan | Composite Index `idx_shows_late_june` | Immutable time bounds allow index range scan on showtimes. |
| **W01** | Insert pending booking | — | Single-row heap page insertion | O(1) row insert; verified constraint integrity. |
| **W02** | Add seat lock to oldest pending order | Seq Scan on pending | Partial Index Seek on `idx_bookings_pending_id` | Atomic seat lock enforced by `PRIMARY KEY (show_id, seat_id)`. |
| **W03** | Confirm oldest pending booking | Seq Scan on pending | Partial Index Seek + single row update | Sub-millisecond state transition to `CONFIRMED`. |
| **W04** | Release expired seat holds (> 10 min) | Seq Scan on bookings | Partial Index on pending + cascade delete on seats | Purges temporary holds without table bloat. |
| **W05** | Surge price update (July weekends) | Seq Scan on shows | Index range update on `idx_shows_movie_starts` | Targeted B-tree update on matching July weekend shows. |
