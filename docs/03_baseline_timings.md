# Phase 3: Baseline Query Timings

**Team:** T0132 · **Section:** E and D · **Repository:** [EdgeRunner-runit/DE_Project_2026](https://github.com/EdgeRunner-runit/DE_Project_2026)

---

## Benchmarking Method

| Parameter | Value |
|-----------|-------|
| **Hardware** | MacBook Pro (Apple M4) |
| **PostgreSQL version** | 18.6 (Postgres.app) |
| **Database** | `bms_capstone` — seed data only, no secondary indexes |
| **Query execution method** | `EXPLAIN (ANALYZE, BUFFERS)` — PostgreSQL actual execution plan |
| **Runs per query** | 3 (average of three reported) |
| **Write queries (W01–W05)** | Wrapped in `BEGIN; … ROLLBACK;` — data unchanged after each run |
| **Secondary indexes present** | None — only PK auto-indexes and UNIQUE auto-indexes from Phase 2 schema |
| **Script used** | `benchmarks/run_benchmark.sh bms_capstone baseline 3` |
| **Raw plans committed at** | `benchmarks/results/baseline/R01.txt … W05.txt` |

---

## Timing Table — All 30 Queries

| SQL Query | Type | Run 1 (ms) | Run 2 (ms) | Run 3 (ms) | Average (ms) |
|-----------|------|----------:|----------:|----------:|-------------:|
| R01: Home page: movies showing in Bengaluru on 2 July 2026 and how many shows each has | READ | 12.909 | 4.924 | 5.048 | 7.627 |
| R02: Showtimes page: shows of movie 2 in Bengaluru on 2 July 2026, grouped by cinema | READ | 4.686 | 3.967 | 3.833 | 4.162 |
| R03: Seat layout: every seat of show 144446 and whether it is already sold | READ | 0.314 | 0.267 | 0.282 | 0.288 |
| R04: Support: open a booking by its code | READ | 0.054 | 0.032 | 0.029 | 0.038 |
| R05: "My bookings": customer 1331's upcoming confirmed shows | READ | 9.251 | 8.081 | 7.956 | 8.429 |
| R06: Search: movies whose title contains "kalki" | READ | 0.155 | 0.140 | 0.135 | 0.143 |
| R07: Cinema dashboard: occupancy of every show at venue 11 on 28 June 2026 | READ | 3.347 | 0.948 | 0.926 | 1.740 |
| R08: Box office: top 10 movies by collections over the weekend of 26–28 June 2026 | READ | 16.730 | 14.609 | 14.098 | 15.146 |
| R09: Seat-lock service: bookings still PENDING more than 10 minutes after they were made | READ | 6.045 | 6.221 | 6.383 | 6.216 |
| R10: Cinema operations: consecutive shows with less than 30 minutes for cleaning (June 2026) | READ | 375.115 | 293.285 | 306.763 | 325.054 |
| R11: Revenue mix: share of ticket revenue from recliner seats, per screen type | READ | 80.543 | 73.036 | 62.375 | 71.985 |
| R12: Fans: customers who booked the same movie more than once | READ | 102.810 | 103.268 | 117.164 | 107.747 |
| R13: Partnerships: offers that have never been redeemed | READ | 15.777 | 19.785 | 15.198 | 16.920 |
| R14: Movie pages: average user rating of 2026 releases with at least 20 reviews | READ | 5.708 | 5.204 | 5.287 | 5.400 |
| R15: Capacity planning: bookings by weekday and hour of booking | READ | 38.400 | 38.815 | 38.039 | 38.418 |
| R16: Cinema partners: cancellation rate per venue for June 2026 shows | READ | 22.057 | 22.661 | 23.846 | 22.855 |
| R17: Cinema operations: seats of screen 101 that were never sold for any June 2026 show | READ | 36.104 | 37.877 | 37.061 | 37.014 |
| R18: Regional insights: collections per language per city in 2026 | READ | 66.484 | 68.717 | 69.751 | 68.317 |
| R19: Distributor report: tickets sold for every June 2026 show of movie 2 | READ | 1425.800 | 1648.580 | 1456.091 | 1510.157 |
| R20: Finance: daily collections and running total for June 2026 | READ | 16.625 | 16.242 | 16.605 | 16.491 |
| R21: Loyalty: 20 customers with the most confirmed bookings in 2026 | READ | 47.933 | 46.734 | 46.303 | 46.990 |
| R22: Support console: all bookings, newest first, page 4,001 (25 per page) | READ | 42.631 | 42.703 | 42.780 | 42.705 |
| R23: Sign-in with mobile number | READ | 0.038 | 0.029 | 0.033 | 0.033 |
| R24: Pricing: average price paid per seat class in each city (2026) | READ | 68.986 | 66.004 | 66.419 | 67.136 |
| R25: Programming: average occupancy of late-night shows (starting 22:30 or later) in June 2026 | READ | 26.311 | 25.997 | 26.049 | 26.119 |
| W01: Checkout: create a PENDING booking for 2 tickets of show 144446 | WRITE | 1.828 | 0.796 | 0.666 | 1.097 |
| W02: Seat lock: the oldest PENDING booking adds 2 more seats | WRITE | 11.208 | 10.670 | 10.671 | 10.850 |
| W03: Payment callback: confirm the oldest PENDING booking | WRITE | 2.404 | 0.670 | 0.661 | 1.245 |
| W04: Seat-lock expiry: release seats held by PENDING bookings older than 10 minutes | WRITE | 8.639 | 8.968 | 8.523 | 8.710 |
| W05: Pricing: 10% higher prices for all July weekend shows of movie 2 | WRITE | 6.445 | 5.841 | 5.648 | 5.978 |
| **Total (sum of all 30 averages)** | | | | | **2,513.388** |

---

## Per-Query Scan Type & Performance Analysis

For each query, the scan type is sourced from the final EXPLAIN (ANALYZE, BUFFERS) plan in the corresponding raw plan file (`benchmarks/results/baseline/`).

---

### R01 — Home page: movies showing in Bengaluru on 2 July 2026 · avg 7.627 ms

**Scan types:** Index Scan on `movies_pkey` · Seq Scan on `screens` · Seq Scan on `venues` · Index Scan on `no_overlapping_shows` (shows)

**Why slow:** The filter `DATE(s.starts_at) = '2026-07-02'` wraps `starts_at` in a function, making it **non-sargable** — the GiST exclusion index on `shows` cannot perform a range scan. PostgreSQL falls back to scanning `venues` and `screens` sequentially to find city_id=1, then fetches matching shows. Run 1 is a cold-cache outlier (12.9 ms) vs warm runs (~5 ms).

---

### R02 — Showtimes page: movie 2 in Bengaluru on 2 July 2026 · avg 4.162 ms

**Scan types:** Seq Scan on `screens` · Seq Scan on `venues` · Index Scan on `no_overlapping_shows` (shows)

**Why slow:** No index on `screens(venue_id)` or `venues(city_id)`, so both tables are scanned sequentially. The `starts_at >= '2026-07-02' AND starts_at < '2026-07-03'` range on `shows` is sargable and uses the GiST index, limiting the show scan. Overall fast due to the `movie_id = 2` filter reducing shows early.

---

### R03 — Seat layout: show 144446 · avg 0.288 ms

**Scan types:** Index Scan on `shows_pkey` · Index Scan on `uq_seats_screen_row_number` (seats) · Index Only Scan on `booking_seats_pkey`

**Why fast:** All three scans use existing PK/UNIQUE auto-indexes. The composite PK `(show_id, seat_id)` on `booking_seats` supports an index-only scan to check sold status. This is one of the booking-critical paths, already performing well at baseline.

---

### R04 — Support: open a booking by code · avg 0.038 ms

**Scan types:** Index Scan on `bookings_booking_code_key`

**Why fast:** `booking_code` has a UNIQUE constraint (auto-indexed). Single-row point lookup on 150k bookings in sub-millisecond time. This is the fastest read query.

---

### R05 — My bookings: customer 1331's upcoming confirmed shows · avg 8.429 ms

**Scan types:** Seq Scan on `bookings` · Index Scan on `shows_pkey` · Seq Scan on `movies` · Seq Scan on `screens` · Seq Scan on `venues`

**Why slow:** No index on `bookings(customer_id, status)`. PostgreSQL must scan all 150k bookings to find customer 1331's confirmed entries, then do further sequential scans up the join chain through movies, screens, venues. A composite index on `(customer_id, status)` would eliminate this.

---

### R06 — Search: movies containing "kalki" · avg 0.143 ms

**Scan types:** Seq Scan on `movies`

**Why deceptively fast:** The `movies` table is only 300 rows — a full sequential scan is trivially fast. At 20× scale (6,000 movies), this would still be small. However, the `ILIKE '%kalki%'` wildcard pattern cannot use a standard B-tree index regardless of table size; a GIN trigram index (`pg_trgm`) is the correct fix for correctness at scale.

---

### R07 — Cinema dashboard: venue 11 occupancy on 28 June 2026 · avg 1.740 ms

**Scan types:** Index Scan on `uq_screens_venue_screen_name` (screens) · Bitmap Heap Scan on `shows` · Bitmap Index Scan on `no_overlapping_shows` · Index Only Scan on `booking_seats_pkey`

**Why decent at baseline:** The venue filter on screens uses the UNIQUE index, then a bitmap scan finds shows via the GiST exclusion index. The `starts_at::date` cast is non-sargable, but the GiST index still supports a partial range evaluation. Run 1 is a warm-up outlier (3.3 ms).

---

### R08 — Box office: top 10 movies, weekend 26–28 June 2026 · avg 15.146 ms

**Scan types:** Seq Scan on `bookings` · Seq Scan on `shows` · Seq Scan on `movies`

**Why slow:** Full scan of 150k bookings to filter by status and show date range, then joins to shows (160k) and movies (300). No index on `bookings(status, show_id)` or `shows(starts_at)`. All three large tables scanned sequentially.

---

### R09 — Pending bookings older than 10 minutes · avg 6.216 ms

**Scan types:** Seq Scan on `bookings`

**Why slow:** To find the small fraction of PENDING bookings, PostgreSQL scans all 150k rows. At baseline, PENDING bookings are <1% of total bookings. A **partial index** `WHERE status = 'PENDING'` would reduce this lookup to microseconds regardless of total table size.

---

### R10 — Shows with <30 min cleaning gap (June 2026) · avg 325.054 ms ⚠️ SECOND SLOWEST

**Scan types:** Seq Scan on `shows` (both sides of self-join)

**Why very slow:** A self-join on `shows` with `s1.screen_id = s2.screen_id AND s2.starts_at > s1.starts_at AND gap < 30 min` is effectively quadratic: PostgreSQL evaluates every pair of shows. With 160k shows in June 2026, this is a massive hash join operation. A composite index on `shows(screen_id, starts_at, ends_at)` would allow the planner to do an index-nested-loop join instead.

---

### R11 — Revenue mix: recliner seat share per screen type · avg 71.985 ms

**Scan types:** Seq Scan on `booking_seats` · Seq Scan on `seats` · Seq Scan on `screens`

**Why slow:** Full scan of all 300k `booking_seats` rows, joined to 94k `seats` and 490 `screens`. No index on `seats(screen_id)` or `booking_seats(seat_id)`. This is an unavoidable full-table aggregation; a covering index on `seats(seat_id, screen_id, seat_class)` would at minimum eliminate heap fetches.

---

### R12 — Fans: customers who booked the same movie more than once · avg 107.747 ms

**Scan types:** Seq Scan on `bookings` · Seq Scan on `shows`

**Why slow:** Full scan of 150k bookings joined to 160k shows, then a GROUP BY aggregation over the full dataset. Requires reading every confirmed booking to find duplicates. A composite index on `bookings(customer_id, show_id, status)` would help narrow this.

---

### R13 — Offers never redeemed · avg 16.920 ms ⚠️ SQL CORRECTNESS BUG

**Scan types:** Seq Scan on `offers` · Seq Scan on `bookings`

**Why returns WRONG result (always empty):** The query uses `WHERE o.offer_code NOT IN (SELECT b.offer_code FROM bookings b)`. Since 85.05% of bookings have `offer_code = NULL`, the subquery returns NULLs. In SQL three-valued logic, `x NOT IN (..., NULL, ...)` evaluates to `UNKNOWN` (not `FALSE`) for every row, so **the WHERE clause eliminates all offers** and returns zero rows — even though unredeemed offers exist.

**Fix required in Phase 4:** Rewrite as `NOT EXISTS (SELECT 1 FROM bookings b WHERE b.offer_code = o.offer_code)` or a `LEFT JOIN ... WHERE b.offer_code IS NULL`.

---

### R14 — Movie ratings: 2026 releases with ≥20 reviews · avg 5.400 ms

**Scan types:** Seq Scan on `movie_reviews` · Seq Scan on `movies`

**Why acceptable:** Scans 32k reviews and 300 movies — relatively small tables. The `release_date >= '2026-01-01'` filter on movies is straightforward. Can be optimized with an index on `movie_reviews(movie_id)` and `movies(release_date)`.

---

### R15 — Booking heatmap: by weekday and hour · avg 38.418 ms

**Scan types:** Seq Scan on `bookings`

**Why unavoidable full scan:** `EXTRACT(ISODOW FROM booked_at)` and `EXTRACT(HOUR FROM booked_at)` are expression-based GROUP BY over all bookings — no selective filter, must read all 150k rows. A covering index on `booked_at` can avoid heap lookups, but the full scan is fundamentally required. Very stable timing (38.0–38.8 ms across 3 runs).

---

### R16 — Cancellation rate per venue, June 2026 · avg 22.855 ms

**Scan types:** Seq Scan on `bookings` · Seq Scan on `shows` · Seq Scan on `screens` · Seq Scan on `venues`

**Why slow:** Four sequential scans on large tables. No index on `shows(starts_at)` or `bookings(show_id)`. The June 2026 date filter must be applied during the scan of 160k shows.

---

### R17 — Seats on screen 101 never sold in June 2026 · avg 37.014 ms

**Scan types:** Seq Scan on `booking_seats` · Seq Scan on `shows` · Index Scan on `uq_seats_screen_row_number` (seats)

**Why slow:** The `NOT EXISTS` correlated subquery checks for each seat of screen 101 whether any `booking_seats` row + joined show falls in June 2026. This triggers repeated scans of `booking_seats` (300k) joined to `shows` (160k). An index on `booking_seats(seat_id)` or `shows(screen_id, starts_at)` would eliminate the repeated scan.

---

### R18 — Regional collections: per language per city in 2026 · avg 68.317 ms

**Scan types:** Seq Scan on `bookings` · Seq Scan on `shows` · Seq Scan on `movies` · Seq Scan on `screens` · Seq Scan on `venues`

**Why slow:** Five sequential scans. `EXTRACT(YEAR FROM s.starts_at) = 2026` is a non-sargable function on `starts_at`, preventing index range scans on shows. Fixing with a sargable range `starts_at >= '2026-01-01' AND starts_at < '2027-01-01'` would allow an index scan.

---

### R19 — Distributor: tickets sold per June 2026 show of movie 2 · avg 1510.157 ms 🔴 SLOWEST

**Scan types:** Seq Scan on `shows` · Seq Scan on `bookings` (repeated per show)

**Why extremely slow (N+1 anti-pattern):** The correlated subquery `(SELECT coalesce(sum(b.num_tickets), 0) FROM bookings b WHERE b.show_id = s.show_id AND b.status = 'CONFIRMED')` runs once per show. Movie 2 has hundreds of June 2026 shows, each triggering a fresh 150k-row scan of `bookings`. This is a textbook N+1 database anti-pattern. Must be rewritten as a JOIN + GROUP BY in Phase 4.

---

### R20 — Finance: daily collections and running total, June 2026 · avg 16.491 ms

**Scan types:** Seq Scan on `bookings`

**Why acceptable:** Scans all 150k bookings once to filter confirmed June 2026 bookings, groups by date, then applies a window function. The window function itself runs on a small result set (30 days). A partial index on `bookings(booked_at) WHERE status = 'CONFIRMED'` would reduce the scan to only confirmed bookings.

---

### R21 — Loyalty: top 20 customers by confirmed bookings in 2026 · avg 46.990 ms

**Scan types:** Seq Scan on `bookings`

**Why slow:** Full scan of 150k bookings to filter by `status = 'CONFIRMED'` and `booked_at >= '2026-01-01'`, then aggregate. A partial index `WHERE status = 'CONFIRMED'` combined with a covering index on `booked_at` and `customer_id` would greatly speed this up.

---

### R22 — Support console: all bookings, page 4,001 (OFFSET 100,000) · avg 42.705 ms ⚠️ INTENTIONAL SLOW

**Scan types:** Seq Scan on `bookings`

**Why slow (by design):** `OFFSET 100000 LIMIT 25` forces PostgreSQL to scan and discard 100,000 rows before returning 25. Cost grows linearly with page number — this is the **deep pagination trap** intentionally included in the workload. The fix is **keyset pagination**: replace `OFFSET` with `WHERE booked_at < $last_seen_value ORDER BY booked_at DESC LIMIT 25`. Notably stable timing across all 3 runs (42.6–42.8 ms), confirming it always reads ~100k rows.

---

### R23 — Sign-in with mobile number · avg 0.033 ms 🟢 FASTEST

**Scan types:** Index Scan on `customers_phone_key`

**Why fastest:** `phone` has a UNIQUE constraint (auto-indexed). Single-row point lookup on 40k customers — sub-millisecond at baseline, requires no optimization. This is the booking path's authentication query.

---

### R24 — Avg price per seat class per city (2026) · avg 67.136 ms

**Scan types:** Seq Scan on `booking_seats` · Seq Scan on `seats` · Seq Scan on `screens` · Seq Scan on `venues`

**Why slow:** Full scan of 300k `booking_seats` joined to 94k seats, 490 screens, and 140 venues. No filter reduces the dataset — it aggregates all historical data. A covering index on `seats(seat_id, screen_id, seat_class)` would avoid heap lookups on seats.

---

### R25 — Late-night show occupancy, June 2026 · avg 26.119 ms

**Scan types:** Seq Scan on `booking_seats` · Seq Scan on `shows` · Seq Scan on `screens`

**Why slow:** `starts_at::time >= '22:30'` is a non-sargable expression on `starts_at`, preventing index usage. Combined with the June 2026 date filter, PostgreSQL scans all 160k shows, 300k booking_seats, and 490 screens. An expression index on `(starts_at::time)` and a range filter on `starts_at` would fix both issues.

---

### W01 — Checkout: create PENDING booking · avg 1.097 ms

**Scan types:** (no scan — plain INSERT)

**Why fast:** A single-row INSERT with no SELECT; PK uniqueness check is an index lookup. Timing variance (0.7–1.8 ms) reflects normal write path overhead. Write queries measured inside `BEGIN … ROLLBACK`.

---

### W02 — Seat lock: oldest PENDING booking adds 2 more seats · avg 10.850 ms

**Scan types:** Index Scan on `bookings_pkey` · Index Scan on `seats_pkey` · Index Scan on `shows_pkey` · Index Only Scan on `booking_seats_pkey`

**Why decent:** All lookups use PK indexes. The inner `SELECT min(booking_id) FROM bookings WHERE status = 'PENDING'` requires a full scan of bookings to find the minimum PENDING — a partial index on `(booking_id) WHERE status = 'PENDING'` would eliminate this.

---

### W03 — Payment callback: confirm oldest PENDING booking · avg 1.245 ms

**Scan types:** Index Scan on `bookings_pkey`

**Why fast:** Similar to W02, the UPDATE uses `booking_id` PK for the final update. The inner `SELECT min(booking_id) WHERE status = 'PENDING'` again scans all bookings; partial index would fix this.

---

### W04 — Seat-lock expiry: delete expired seats · avg 8.710 ms

**Scan types:** Seq Scan on `bookings` · Index Scan on `uq_booking_seats_booking_seat`

**Why moderate:** Full scan of bookings to find PENDING rows older than 10 minutes (same problem as R09), then uses an index to find and delete corresponding `booking_seats` rows. Partial index on `bookings(status)` would fix the scan.

---

### W05 — Surge pricing: 10% higher for July weekend shows of movie 2 · avg 5.978 ms

**Scan types:** Seq Scan on `shows`

**Why moderate:** No index on `shows(movie_id, starts_at)`. Must scan all 160k shows to find movie 2's July weekend shows. A composite index on `(movie_id, starts_at)` would make this a fast index-range scan.

---

## Summary

| Metric | Value |
|--------|-------|
| **Total baseline time (sum of 30 averages)** | **2,513.388 ms** |
| **Slowest query** | R19 — 1,510.157 ms (correlated subquery N+1 anti-pattern) |
| **Second slowest** | R10 — 325.054 ms (shows self-join, quadratic without index) |
| **Fastest query** | R23 — 0.033 ms (UNIQUE index point lookup on phone) |
| **Second fastest** | R04 — 0.038 ms (UNIQUE index point lookup on booking_code) |
| **Dominant scan type** | Seq Scan (expected at baseline — no secondary indexes present) |
| **SQL bug found** | R13 — `NOT IN` with NULLs always returns empty; fix with `NOT EXISTS` |
| **Intentionally slow query** | R22 — `OFFSET 100000` deep pagination trap |
| **Queries already fast at baseline** | R03, R04, R06, R07, R23 (use existing PK/UNIQUE auto-indexes) |

The Phase 4 optimization effort will focus primarily on:
1. **R19** — rewrite correlated subquery → JOIN + GROUP BY
2. **R10** — composite index on `shows(screen_id, starts_at, ends_at)`
3. **R13** — fix SQL correctness bug (NOT IN → NOT EXISTS)
4. **R09, W03, W04** — partial index on `bookings(status)`
5. **R01, R07, R18, R25** — fix non-sargable date/time function casts
6. **R06** — GIN trigram index for `ILIKE '%text%'`
7. **R22** — keyset pagination to replace OFFSET
