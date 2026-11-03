# Phase 1: Problem Understanding

**Team:** T0132 · **Section:** E · **Repo:** https://github.com/EdgeRunner-runit/DE_Project_2026

---

## How BookMyShow Works (Domain Context)

BookMyShow sells movie tickets seat-by-seat. A **venue** (e.g., PVR, INOX) contains multiple **screens**. Each screen has a fixed **seat layout** divided into classes (CLASSIC, PRIME, RECLINER). A **show** is a single movie playing on a specific screen at a specific time. When a customer books, chosen seats are held in a `PENDING` state for up to 10 minutes; if payment succeeds they become `CONFIRMED`, otherwise the hold expires and seats are released. The dataset covers shows from April – July 2026 with ~150k bookings and ~300k booking_seats.

The existing database has **no documented schema, no constraints, and no indexes**—only raw CSV exports survive. The goal of this project is to rebuild a correct, well-constrained schema, measure query performance, optimize it, and prove it can handle 20× growth.

---

## Problem Statements: P1 – P8

| # | Problem Reported | Stakeholder | Classification | Related Queries |
|---|-----------------|-------------|----------------|-----------------|
| P1 | "Now showing, showtimes and search pages are slow on Friday mornings." | Movie-goers, Customer App Team | **Customer-facing / Real-time** | R01, R02, R06 |
| P2 | "Seat layout screen is too slow and two people must never get the same seat." | Customers, Booking Engine | **Customer-facing / Real-time** | R03, W01, W02 |
| P3 | "Pending-payment queue, confirmations and seat-lock expiry jobs lag." | Payments Service, Seat-lock Daemon | **System / Real-time** | R09, W03, W04 |
| P4 | "My bookings, booking lookup and sign-in are too slow." | Customers, Support Agents | **Customer-facing / Real-time** | R04, R05, R22, R23 |
| P5 | "Cinema managers need occupancy, cleaning-gap checks and never-sold seats." | Cinema / Venue Managers | **Operational / Interactive** | R07, R10, R17, R25 |
| P6 | "Offers never redeemed" report is always empty." | Partnerships Team | **Reporting (Data Bug)** | R13 |
| P7 | "Distributors want box-office and per-show ticket counts during release weekends." | Film Distributors, Studios | **Reporting / Commercial** | R08, R19, W05 |
| P8 | "Finance and insight reports time out, and volume will grow 20×." | Finance, BI / Insights Team | **Reporting / Analytics** | R11, R12, R14, R15, R16, R18, R20, R21, R24 |

---

## Detailed Analysis

### P1 — Now Showing, Showtimes & Search (R01, R02, R06)

**Business need:** On every Friday morning (new release day), millions of users simultaneously open the app to see what is playing, view showtimes by cinema, and search for movie titles. Response must feel instant (< 200 ms target).

**Stakeholder:** Movie-goers using the Customer App.

**Classification:** Customer-facing / Real-time.

**Why it is slow:**
- R01 and R02 join `shows → screens → venues` and filter by city and date. Without indexes on `screens(venue_id)`, `shows(screen_id)`, and `shows(starts_at)`, the engine performs full sequential scans on 160,000+ shows.
- R02 also wraps `starts_at` in a range filter, but R01 uses `DATE(starts_at)` which is non-sargable (index cannot be used when a column is wrapped in a function).
- R06 uses `ILIKE '%kalki%'` (wildcard on both sides), which standard B-Tree indexes cannot serve; requires a trigram GIN index (`pg_trgm` extension).

**Assumption:** "Friday mornings" refers to peak load (8 AM – 12 PM); the query results must be live (no caching) for accurate showtime availability.

---

### P2 — Seat Layout & Seat Locking (R03, W01, W02)

**Business need:** The seat grid for a specific show must render instantly (< 100 ms). When a customer taps "Book", two concurrent users must never acquire the same seat—this is a hard correctness requirement, not just a performance one.

**Stakeholder:** Customers at checkout, Booking Engine service.

**Classification:** Customer-facing / Real-time (also has a correctness/concurrency dimension).

**Why it is slow and unsafe:**
- R03 loads every seat of a screen and LEFT JOINs all `booking_seats` to check if each seat is taken. Without an index on `booking_seats(show_id, seat_id)`, this scans 300k rows for every seat-grid render.
- W01 inserts a new `PENDING` booking. W02 inserts into `booking_seats` with `ON CONFLICT (show_id, seat_id) DO NOTHING` — this `UNIQUE` constraint (or composite PK) on `(show_id, seat_id)` is the database-level guarantee against double-selling a seat. Without it, two concurrent sessions could insert the same seat.

**Assumption:** Seat locking is enforced exclusively at the DB layer (not via an application-level distributed lock) for correctness.

---

### P3 — Payments & Seat-Lock Expiry (R09, W03, W04)

**Business need:** A background daemon runs every few seconds to find PENDING bookings older than 10 minutes and release their seat holds. A payment-callback service confirms bookings when UPI/card payments succeed. Both must execute with minimal latency and without causing lock contention on hot tables.

**Stakeholder:** Payments Service, Seat-lock expiry daemon.

**Classification:** System / Real-time (background, latency-sensitive daemon processes).

**Why it is slow:**
- R09 scans the full `bookings` table (150k rows) to find the tiny fraction with `status = 'PENDING'`. A partial index `WHERE status = 'PENDING'` would shrink this lookup dramatically.
- W04 deletes rows from `booking_seats` joined back to `bookings`. Frequent deletes without periodic `VACUUM` leave dead tuples, bloating the table and slowing future scans.
- W03 (confirm booking) needs a fast path to find the oldest pending booking (`SELECT min(booking_id) ... WHERE status = 'PENDING'`) without a full scan.

**Assumption:** PENDING bookings are a tiny minority (< 1%) of total bookings at any point in time.

---

### P4 — My Bookings, Booking Lookup & Sign-In (R04, R05, R22, R23)

**Business need:** Customers need their booking history within 100 ms. Support agents need to pull up any booking by its reference code instantly. Sign-in via mobile number must be sub-second to not create friction.

**Stakeholder:** Customers using "My Bookings", Support Agents on the support console.

**Classification:** Customer-facing / Real-time.

**Why it is slow:**
- R04 (`WHERE booking_code = 'BMSA45E9F9'`) and R23 (`WHERE phone = '7700001331'`) are point lookups that need unique indexes. Without them, they sequentially scan 150k and 40k rows respectively.
- R05 (upcoming bookings for customer 1331) joins 5 tables and filters by `customer_id`, `status = 'CONFIRMED'`, and `starts_at >= '2026-07-01'`. Needs a composite index on `bookings(customer_id, status)`.
- R22 (`OFFSET 100000 LIMIT 25`) is a textbook deep-pagination performance trap. PostgreSQL must process 100,025 rows to return 25—cost grows linearly with the page number. This is the intended "slowest query" in the workload.

**Assumption:** Booking codes are globally unique; phone numbers are unique per customer account.

---

### P5 — Cinema Manager Operations (R07, R10, R17, R25)

**Business need:** Cinema managers need an operations dashboard: real-time occupancy per show, warnings when back-to-back shows have less than 30 minutes for cleaning, a list of seats never sold (potentially broken), and late-night show attendance summaries.

**Stakeholder:** Cinema / Venue Managers.

**Classification:** Operational / Interactive (not real-time like booking, but must respond within seconds, not minutes).

**Why it is slow:**
- R07 (occupancy per show at venue 11) uses `starts_at::date = '2026-06-28'`, another non-sargable cast. Full scan of shows, then aggregation over booking_seats.
- R10 (cleaning gap check) is a **self-join of shows on shows**: `s1.screen_id = s2.screen_id AND s2.starts_at > s1.starts_at AND gap < 30 min`. On 160k shows, this is quadratic without a composite index on `(screen_id, starts_at, ends_at)`.
- R17 (never-sold seats) uses `NOT EXISTS` correlated subquery per seat—each seat triggers a lookup into `booking_seats`.

**Assumption:** Cinema managers accept a response time of up to 5 seconds for dashboard reports; real-time accuracy is required (no stale caches).

---

### P6 — Offers Never Redeemed (R13)

**Business need:** The partnerships team needs to know which promotional offer codes have never been used by any customer, so they can renew, renegotiate, or remove those deals.

**Stakeholder:** Partnerships / Marketing Team.

**Classification:** Reporting. **Note: This is a data correctness bug, not a performance problem.**

**Root cause:** The query uses:
```sql
WHERE o.offer_code NOT IN (SELECT b.offer_code FROM bookings b)
```
In SQL's three-valued logic, `NOT IN` with a subquery that contains `NULL` values evaluates the entire `WHERE` clause to `UNKNOWN` (not `FALSE`) for every row, causing the query to return zero rows. Since most bookings have `NULL` in `offer_code` (no offer applied), the subquery returns NULLs, and `NOT IN` silently returns nothing.

**Fix (Phase 4):** Rewrite using `NOT EXISTS` or a `LEFT JOIN ... WHERE b.booking_id IS NULL`.

**Assumption:** `offer_code` is nullable in `bookings` (confirmed by the data: most bookings do not use an offer code). This is correct behaviour—it is the SQL `NOT IN` that is wrong.

---

### P7 — Distributor Box-Office Reports (R08, R19, W05)

**Business need:** Film distributors settle revenue shares with BookMyShow weekly. They need accurate box-office totals (total collection per movie over a weekend) and show-level attendance for every show of their movie. Pricing teams also do weekend surge pricing updates.

**Stakeholder:** Film Distributors, Studios, Pricing / Revenue Management.

**Classification:** Reporting / Commercial (can tolerate up to 1–2 seconds; run periodically, not on user demand).

**Why it is slow:**
- R08 (top 10 movies by weekend collections) aggregates across multiple joins on `bookings`, `shows`, `movies` for a 3-day window.
- R19 uses a **correlated subquery** inside the `SELECT` list — for each show of movie 2 in June (potentially thousands of shows), it runs a separate `SELECT sum(num_tickets) FROM bookings` query. This is an N+1 anti-pattern inside the database engine.
- W05 (surge pricing update) updates `base_price` across potentially hundreds of shows; needs index on `(movie_id, starts_at)`.

**Assumption:** Distributors run these reports during off-peak hours (not simultaneously with booking traffic).

---

### P8 — Finance & Insight Reports (R11, R12, R14–R16, R18, R20, R21, R24)

**Business need:** Finance, BI, and executive teams need comprehensive insight reports: revenue breakdown by seat class and screen type, top loyal customers, daily running revenue totals, regional collections by language, hourly booking traffic heatmaps, cancellation rates by venue, and average prices by city and seat class. These currently time out and will become completely unusable at 20× volume.

**Stakeholder:** Finance Team, Business Intelligence / Insights Team, Senior Executives.

**Classification:** Reporting / Analytics (batch-style; can tolerate up to 5 seconds on seed data, must still meet targets on large data).

**Why it is slow and won't scale:**
- All these queries perform full-table aggregations on `bookings` (150k rows) and `booking_seats` (300k rows), joining multiple tables.
- Functions on columns (`EXTRACT(YEAR FROM starts_at)`, `booked_at::date`) break index usage.
- R15 (`EXTRACT(ISODOW FROM booked_at)`) groups all 150k bookings by weekday and hour—unavoidably a full scan, but covering indexes can avoid heap lookups.
- R20 uses a window function (`SUM(...) OVER (ORDER BY day)`) on an aggregated subquery—the bottleneck is the inner aggregation.
- At 20× volume (~3M bookings, ~6M booking_seats), all these queries will require either composite/covering indexes, partial indexes on `status = 'CONFIRMED'` (since cancelled bookings are noise in most finance queries), or materialized/summary tables refreshed periodically.

**Assumption:** Finance reports can tolerate up to 5 seconds on large data. Stale data up to 1 hour is acceptable for analytical reports (allows materialized view approach).

---

## Summary: Classification Grid

| Classification | Problems | Performance Target |
|---------------|----------|-------------------|
| **Customer-facing / Real-time** | P1, P2, P3, P4 | < 5 ms (booking path), < 250 ms (browsing) |
| **Operational / Interactive** | P5 | < 5,000 ms |
| **Reporting / Analytics** | P6 (bug), P7, P8 | < 5,000 ms on large data; correctness fix for P6 |

---

## Key Assumptions (Global)

1. All timestamps in the database are stored with timezone (`TIMESTAMPTZ`) anchored to IST (+05:30).
2. A booking with `status = 'CANCELLED'` never has rows in `booking_seats` (seats are freed when cancelled).
3. `offer_code` is nullable in `bookings`; a NULL means no offer was applied.
4. `review_text` is nullable; a customer can submit a numeric rating without writing a review.
5. `screens.total_seats` is a derived/redundant column (can be computed from `COUNT(seats)`), kept for performance.
6. The database enforces seat uniqueness per show at the DB layer via `PRIMARY KEY (show_id, seat_id)` on `booking_seats`.
7. No index changes are made in Phase 2; the baseline in Phase 3 reflects a schema with only PK and UNIQUE auto-indexes.
