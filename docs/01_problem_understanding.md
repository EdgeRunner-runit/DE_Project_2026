# Phase 1: Problem Understanding

**Team:** T0132 · **Course:** DBMS · **Repository:** https://github.com/EdgeRunner-runit/DE_Project_2026

---

## 1. Problem Classification & Stakeholder Mapping

| # | Problem Reported | Business Need (in our own words) | Stakeholder | Classification | Related Queries |
|---|------------------|----------------------------------|-------------|----------------|-----------------|
| **P1** | Now showing, showtimes and search pages are slow on Friday mornings | Instant discovery of movies, screens, and showtimes during peak release-day rushes without app lag or user drop-off. | **movie-goer** | **customer-facing / real-time** | R01, R02, R06 |
| **P2** | Seat layout screen and seat locking are too slow; two people must never get the same seat | Rapid rendering of interactive seat grids and strict ACID concurrency control to lock seats without race conditions or double-booking. | **movie-goer**, **payments/seat-lock service** | **customer-facing / real-time** | R03, W01, W02 |
| **P3** | Pending-payment queue, confirmations and seat-lock expiry jobs lag | Low-latency background workers to quickly verify payment webhooks and release expired 10-minute holds back into inventory. | **payments/seat-lock service** | **customer-facing / real-time** | R09, W03, W04 |
| **P4** | Customers and support wait too long for My bookings, booking lookup and sign-in | Immediate single-record retrieval for customer self-service, OTP/mobile login, and agent ticket resolution without deep scanning. | **support**, **movie-goer** | **customer-facing / real-time** | R04, R05, R22, R23 |
| **P5** | Cinema managers need occupancy, cleaning-gap checks and never-sold seats per screen | Operational oversight on auditorium capacity, safety turnaround gaps (< 30 min) between consecutive shows, and unsellable broken seats. | **cinema/venue manager**, **programming team** | **reporting / analytics** | R07, R10, R17, R25 |
| **P6** | Partnerships' "offers never redeemed" report is always empty | Accurate tracking of promotional discount redemptions to evaluate marketing contracts, fixing the zero-result query bug caused by NULL values. | **partnerships** | **reporting / analytics** | R13 |
| **P7** | Distributors want box-office and per-show ticket counts during release weekends | Accurate box-office earnings calculation and per-show attendance reporting for distributor settlements and dynamic weekend surge pricing. | **distributor** | **reporting / analytics** | R08, R19, W05 |
| **P8** | Finance and insight reports time out, and volume will grow 20× | Scalable business intelligence analytics on revenue streams, customer loyalty, and cancellation trends that compute efficiently even at 20× data volume. | **finance** | **reporting / analytics** | R11, R12, R14, R15, R16, R18, R20, R21, R24 |

---

## 2. Problem Details & Performance Targets

### Customer-Facing / Real-Time (P1 – P4)
* **Performance Target:** Real-time booking path < 5 ms; browsing / interactive queries < 250 ms.
* **P1 (movie-goer):** Needs sub-200 ms response times for search and showtimes under peak traffic spikes; queries currently fail due to non-sargable functions (`DATE()`) and missing join indexes.
* **P2 (movie-goer, payments/seat-lock service):** Critical transactional path where concurrency safety is paramount; requires database-level constraint `PRIMARY KEY (show_id, seat_id)` to prevent double-booking.
* **P3 (payments/seat-lock service):** Fast daemon processing to clean up expired locks (`status = 'PENDING'`) and prevent lock contention on the hot bookings table.
* **P4 (support, movie-goer):** Point lookups by unique credentials (phone, booking code) must use index lookups, avoiding costly sequential scans and large `OFFSET` traversals.

### Reporting / Analytics (P5 – P8)
* **Performance Target:** Batch execution under 5,000 ms on seed data and large (20×) dataset.
* **P5 (cinema/venue manager, programming team):** Periodic operational reports to monitor turnaround buffers and auditorium utilization without locking user tables.
* **P6 (partnerships):** Fixes query `R13` where `NOT IN (SELECT offer_code ...)` evaluates to NULL/empty because `bookings.offer_code` has NULL values; must rewrite to `NOT EXISTS`.
* **P7 (distributor):** Aggregates box-office figures for commercial auditing; eliminates the correlated subquery anti-pattern in `R19`.
* **P8 (finance):** Multi-table aggregation crunching large volume; requires composite/covering indexes, partitioning, and summary tables to survive 20× data growth.

---

## 3. Assumptions

1. **Timezone:** All timestamps are recorded in IST (`TIMESTAMPTZ`, UTC+05:30).
2. **Nullable Fields:** `offer_code` is NULL when no discount is applied; `review_text` is NULL when a customer submits only a numeric rating.
3. **Seat State Invariant:** Cancelled bookings have their associated rows removed from `booking_seats` upon cancellation or expiry.
4. **Data Redundancy:** `screens.total_seats` and `shows.ends_at` are stored for operational lookup performance and constraint checks, despite being derivable from related tables.
5. **Concurrency Boundary:** Seat locking and double-booking prevention must be enforced at the database level via constraints and transactions, not relying on application-level checks.
6. **Query Invariance:** The logic and returned datasets of all 30 queries must remain identical after schema fixes and optimization in Phase 4.
