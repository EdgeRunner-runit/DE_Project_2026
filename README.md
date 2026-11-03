# BookMyShow Movie & Event Ticketing Database: DBMS Project

**Course:** Database Management Systems · **Year:** B.Tech 2nd year · **Team size:** 4
**Database:** PostgreSQL 15 or newer · **Final submission:** Mon 23 Nov 2026
**Topics used:** Data types & constraints · Keys & relationships · Normalization · Query execution plans · Indexing · Query optimization · VACUUM/ANALYZE · Partitioning & sharding

## Files in this folder

| Path | What it is |
|------|------------|
| `README.md` | This project brief |
| `seed_data.zip` | 11 CSV files (300,389 bookings): the only input for Phase 2. Unzip it to get `seed_data/` |
| `queries/workload_30.sql` | The 30 queries for Phase 3 (do not edit) |
| `benchmarks/run_benchmark.sh` | Timing script: 3 runs per query, average, raw plans saved |
| `CHECKPOINTS.md` | Checkpoint dates and the files each one needs (DE and AP repos) |

**Getting started:** **clone this repository and push it into your team's DE repo** (the DE repo you submitted in the form); the steps are in [`CHECKPOINTS.md`](CHECKPOINTS.md). Keep the structure shown in [Repository structure](#repository-structure-submit-exactly-this). Unzip `seed_data.zip` inside your project folder, but don't commit the CSV files. Deadlines are in [`CHECKPOINTS.md`](CHECKPOINTS.md). Then begin with Phase 1.

---

## Team details (fill in before you start)

| Role | Name | Enrollment No. | GitHub Username |
|------|------|----------------|-----------------|
| Group Lead |Piyush Alagh|2501010333 | https://github.com/EdgeRunner-runit|
| Member 2 |Aujasya Rajput|2501010564| https://github.com/Aujasyarajput18|
| Member 3 | Kushal garg| 2501010241| https://github.com/kshlgrg|
| Member 4 | Aryan Damara| 2501010094| https://github.com/AryanDamara|

**Team No.:** T0132 · **Section:** E and D  · **Repository URL:** https://github.com/EdgeRunner-runit/DE_Project_2026

---

## How this project works

| Phase | What you do | You submit | Counts toward | Marks |
|-------|-------------|------------|---------------|------:|
| 1 | Understand the problem statements | `docs/01_problem_understanding.md` | Query Execution | 2 |
| 2 | Work out the database schema **from the seed data** and load it | `sql/01_schema.sql`, `sql/02_load_data.sql`, `docs/02_schema_design.md` | Query Execution | 5 |
| 3 | Run the **30 given SQL queries** and record their execution time | `docs/03_baseline_timings.md`, `benchmarks/results/baseline/` | Query Execution | 3 |
| 4 | Optimize the queries and record the new times | `sql/05_indexes.sql`, `sql/06_optimized_queries.sql`, `docs/04_optimization_report.md`, `benchmarks/results/optimized/` | Code Optimization | 16 |
| 5 | Scalability test on the **large dataset** (given later by faculty) and final report | `docs/05_scalability_report.md`, `benchmarks/results/large/` | Code Optimization | 14 |
| | **Total** | | | **40** |

---

## Phase 1: Problem statements

BookMyShow sells cinema tickets **seat by seat**. A **venue** (PVR, INOX, …) has several **screens**; every screen has a fixed **seat layout** (rows A, B, C … with classic, prime and recliner seats). Each **show** is a movie playing on a screen at a time—and two shows can never overlap on the same screen. When a customer books, the chosen seats are held while they pay; a seat can be sold **only once per show**. Bookings include a convenience fee, optional food & beverages and offers. You have joined the BookMyShow data team (data covers shows from April to early July 2026).

The current database was put together quickly by an earlier team. It has **no documented schema** (only data exports survive), and the product teams are complaining:

| # | Problem reported | Team | Related queries |
|---|------------------|------|-----------------|
| P1 | "**Now showing, showtimes and search** pages are slow on Friday mornings." | Customer app | R01, R02, R06 |
| P2 | "The **seat layout** screen and **seat locking** are too slow, and two people must never get the same seat." | Booking engine | R03, W01, W02 |
| P3 | "**Payments**: the pending-payment queue, confirmations and seat-lock expiry jobs lag." | Payments / Seat lock | R09, W03, W04 |
| P4 | "Customers and support wait too long for **My bookings**, booking lookup and sign-in." | Customer app / Support | R04, R05, R22, R23 |
| P5 | "**Cinema managers** need occupancy, cleaning-gap checks and never-sold seats per screen." | Cinema operations | R07, R10, R17, R25 |
| P6 | "Partnerships' "**offers never redeemed**" report is always **empty**." | Partnerships | R13 |
| P7 | "**Distributors** want box-office and per-show ticket counts during release weekends." | Distributors | R08, R19, W05 |
| P8 | "Finance and insight reports (revenue mix, regional collections, ratings, loyalty, booking patterns, cancellations) time out, and volume will grow **20×**." | Finance / Insights | R11, R12, R14, R15, R16, R18, R20, R21, R24 |

**Your job:**
1. Rebuild a correct, well-constrained schema from the data exports (Phase 2).
2. Measure how the 30 most important queries perform today (Phase 3).
3. Make them fast **without changing their results** (Phase 4).
4. Prove the database will survive next year's growth (Phase 5).

**Deliverable for Phase 1** (`docs/01_problem_understanding.md`, at most 1 page):
- For each problem P1–P8, write in your own words what the business needs and which **stakeholder** is affected (movie-goer, cinema/venue manager, distributor, programming team, payments/seat-lock service, partnerships, finance, support).
- Classify each problem as **customer-facing / real-time** or **reporting / analytics**. This decides your performance targets later.
- List any assumptions you make.

---

## Phase 2: Work out the schema from the seed data

You receive **`seed_data.zip`**. Unzip it to get a folder **`seed_data/`** with 11 CSV files, a real export of the production data:

| File | Rows | What it contains |
|------|-----:|------------------|
| `cities.csv` | 10 | Cities |
| `venues.csv` | 140 | Cinemas |
| `screens.csv` | 490 | Screens (auditoriums) in each cinema |
| `seats.csv` | 94,056 | Seat layout of every screen |
| `movies.csv` | 300 | Movies |
| `shows.csv` | 160,034 | Shows (a movie on a screen at a time), 1 Apr – 7 Jul 2026 |
| `customers.csv` | 40,000 | BookMyShow customers |
| `offers.csv` | 25 | Discount offers |
| `bookings.csv` | 150,094 | Bookings (one per checkout) |
| `booking_seats.csv` | 300,389 | Seats sold in each booking |
| `movie_reviews.csv` | 32,510 | Ratings and reviews of movies |

The first line of every file is the header (column names). Here are the headers and the first rows of each file:

**cities.csv**
```
city_id,city_name,state
1,Bengaluru,Karnataka
2,Mumbai,Maharashtra
```

**venues.csv**
```
venue_id,venue_name,city_id,chain,address
1,PVR Forum Mumbai,2,PVR,"Ring Road, Mumbai"
2,INOX Orion Hyderabad,4,INOX,"Mall Road, Hyderabad"
```

**screens.csv**
```
screen_id,venue_id,screen_name,screen_type,total_seats
1,1,Audi 1,STANDARD,165
2,1,Audi 2,STANDARD,192
```

**seats.csv**
```
seat_id,screen_id,row_label,seat_number,seat_class
1,1,A,1,CLASSIC
2,1,A,2,CLASSIC
```

**movies.csv**
```
movie_id,title,language,certificate,duration_min,release_date
1,Jawan Returns,Telugu,UA,137,2026-04-18
2,Animal Returns,Kannada,UA,174,2026-06-19
```

**shows.csv**
```
show_id,movie_id,screen_id,starts_at,ends_at,format,base_price
1,153,1,2026-04-01 10:25:00+05:30,2026-04-01 13:21:00+05:30,2D,180.00
2,79,1,2026-04-01 14:55:00+05:30,2026-04-01 17:33:00+05:30,2D,180.00
```

**customers.csv**
```
customer_id,full_name,email,phone,city_id,created_at
1,Vivaan Sharma,vivaan_sharma1@gmail.com,7700000001,2,2022-07-13 16:20:46+05:30
2,Aditya Sharma,aditya_sharma2@gmail.com,7700000002,4,2026-01-10 20:14:40+05:30
```

**offers.csv**
```
offer_code,description,discount_pct,max_discount,valid_from,valid_to
AMAZONPAY17,Buy one get one,20,150.00,2026-03-01,2026-12-31
AMAZONPAY7,Buy one get one,20,250.00,2026-03-01,2026-12-31
```

**bookings.csv**
```
booking_id,booking_code,customer_id,show_id,booked_at,num_tickets,ticket_amount,convenience_fee,fnb_amount,offer_code,discount,total_amount,payment_method,status
1,BMS0004F28,33748,105064,2026-06-01 02:09:00+05:30,2,468.00,46.80,0.00,,0.00,514.80,WALLET,CONFIRMED
2,BMS0006E17,25693,145502,2026-06-26 17:01:00+05:30,1,234.00,23.40,0.00,,0.00,257.40,GIFT_CARD,CONFIRMED
```

**booking_seats.csv**
```
booking_id,show_id,seat_id,price
1,105064,31535,234.00
1,105064,31536,234.00
```

**movie_reviews.csv**
```
review_id,movie_id,customer_id,rating,review_text,created_at
1,209,29471,5,,2026-04-01 16:08:00+05:30
2,25,21052,7,,2026-04-01 17:00:00+05:30
```

Open the files yourself (a spreadsheet, `head`, or `SELECT` after a quick load into a scratch table) and study the data carefully. **Nobody will give you the CREATE TABLE statements.** Working them out *is* the task.

### 2.1 What you must identify (for every table)
1. **Table name and column names.** Use exactly the file names and CSV headers. The 30 queries depend on them.
2. **Data type** of every column. Choose the *right* type, not just `TEXT` everywhere. Think about money, timestamps with a time-zone offset, yes/no columns, small whole numbers, decimals and short codes.
3. **Primary key.** Is it one column, or a combination? (Look closely at `booking_seats`: what stops the same seat being sold twice for one show? What identifies a seat inside a screen?)
4. **Foreign keys.** Which column points to which table? What should happen **ON DELETE** (CASCADE, RESTRICT or SET NULL), and why?
5. **NOT NULL vs NULL.** Some columns are empty in some rows. Find out **when** and **why**, and decide which columns must never be empty. When are `offer_code` and `review_text` empty? Why does a cancelled booking have no rows in `booking_seats`?
6. **UNIQUE** columns (natural candidate keys such as emails, phone numbers, codes and handles).
7. **CHECK constraints.** Write at least **12** that the data obeys and the business needs. Look for formats (booking codes, row letters), allowed values (chains, screen types, seat classes, formats, statuses, certificates), time order, money rules (how `total_amount` is built from the other amounts), and a rule no simple CHECK can express: two shows on the same screen must never overlap in time (research PostgreSQL **exclusion constraints** with `btree_gist`).
8. **Relationships and cardinalities** (1:1, 1:N, M:N). Draw the **ER diagram** (image + Mermaid code).
9. **Normal form.** Show that each table is in 3NF/BCNF (list its functional dependencies). Point out any column that is *derived or redundant* (hint: `screens.total_seats` vs `seats`; `bookings.ticket_amount` vs `booking_seats.price`; `booking_seats.show_id` vs `bookings.show_id`; `shows.ends_at` vs the movie duration) and say whether keeping it is justified.

### 2.2 Rules for your schema
- Create every table in a schema named **`bms`**: `CREATE SCHEMA bms;` and `SET search_path TO bms;`
- In this phase create **only constraints**: PK, FK, UNIQUE, NOT NULL, CHECK. **Do not create any other index yet.** (PostgreSQL automatically indexes PRIMARY KEY and UNIQUE columns; that's allowed. Note which indexes exist.) Your baseline in Phase 3 must reflect a database *without* tuning.
- Your constraints must accept **all** rows of the seed data. If a load fails, either your constraint is wrong or you found a data problem. Explain which in your design doc.

### 2.3 Load the data
Write `sql/02_load_data.sql` using `\copy`, loading tables in the right order (parents before children):

```sql
SET search_path TO bms;
\copy cities FROM 'seed_data/cities.csv' WITH (FORMAT csv, HEADER true)
-- ... the other tables, in an order that satisfies your foreign keys
ANALYZE;
```

Then verify the row counts match the table above, and run at least **3 integrity checks** of your own (e.g. "every booked seat belongs to the screen of that show", "`num_tickets` equals the number of seats held by an active booking", "no two shows overlap on one screen"). Paste the results into `docs/02_schema_design.md`.

### Phase 2 deliverables
- `sql/01_schema.sql`: runs top-to-bottom on an empty database without errors
- `sql/02_load_data.sql`: loads all 11 files without errors
- `docs/02_schema_design.md`: data dictionary (table · column · type · constraint · *why*), ER diagram, FDs and normal form per table, integrity-check results, and every data problem you found

---

## Phase 3: Run the 30 queries and record the time

The file **`queries/workload_30.sql`** contains **30 queries**: 25 reads (`R01`–`R25`) and 5 writes (`W01`–`W05`). They're also listed in the [Appendix](#appendix-the-30-queries). **Do not modify them.** If a query fails, your schema doesn't match the seed data; fix the schema, not the query.

### 3.1 How to measure (everyone must use the same method)
- Run each query with `EXPLAIN (ANALYZE, BUFFERS)` and read the **`Execution Time`** at the bottom.
- Run each query **3 times** and record the **average** of the three `Execution Time` values. Keep all three runs in the raw plan file.
- Write queries (`W01`–`W05`) must be measured inside `BEGIN; … ROLLBACK;` so the data does not change.
- Close other heavy applications while measuring, and use the **same laptop** for Phase 3 and Phase 4.

The helper script does all of this for you:
```bash
./benchmarks/run_benchmark.sh <your_database> baseline
# → benchmarks/results/baseline/summary.csv   (avg, median, min, max, scan types)
# → benchmarks/results/baseline/R01.txt …     (full plans of all 3 runs)
```
> ⚠️ One of the 30 queries takes **noticeably longer** than the others on the seed data. That's intentional. Let it finish, and don't skip it.

### 3.2 Deliverable: the timing table
In `docs/03_baseline_timings.md`, fill this table for **all 30** queries:

| SQL Query | Type | Run 1 (ms) | Run 2 (ms) | Run 3 (ms) | Average (ms) |
|---|---|---:|---:|---:|---:|
| R01: Home page: movies showing in Bengaluru on 2 July 2026 and how many shows each has | READ | | | | |
| R02: Showtimes page: shows of movie 2 in Bengaluru on 2 July 2026, grouped by cinema | READ | | | | |
| R03: Seat layout: every seat of show 144446 and whether it is already sold | READ | | | | |
| R04: Support: open a booking by its code | READ | | | | |
| R05: "My bookings": customer 1331's upcoming confirmed shows | READ | | | | |
| R06: Search: movies whose title contains "kalki" | READ | | | | |
| R07: Cinema dashboard: occupancy of every show at venue 11 on 28 June 2026 | READ | | | | |
| R08: Box office: top 10 movies by collections over the weekend of 26–28 June 2026 | READ | | | | |
| R09: Seat-lock service: bookings still PENDING more than 10 minutes after they were made (checked at 23:59, 30 Jun 2026) | READ | | | | |
| R10: Cinema operations: consecutive shows on the same screen with less than 30 minutes for cleaning (June 2026) | READ | | | | |
| R11: Revenue mix: share of ticket revenue from recliner seats, per screen type | READ | | | | |
| R12: Fans: customers who booked the same movie more than once | READ | | | | |
| R13: Partnerships: offers that have never been redeemed | READ | | | | |
| R14: Movie pages: average user rating of 2026 releases with at least 20 reviews | READ | | | | |
| R15: Capacity planning: bookings by weekday and hour of booking | READ | | | | |
| R16: Cinema partners: cancellation rate per venue for June 2026 shows | READ | | | | |
| R17: Cinema operations: seats of screen 101 that were never sold for any June 2026 show | READ | | | | |
| R18: Regional insights: collections per language per city in 2026 | READ | | | | |
| R19: Distributor report: tickets sold for every June 2026 show of movie 2 | READ | | | | |
| R20: Finance: daily collections and running total for June 2026 | READ | | | | |
| R21: Loyalty: 20 customers with the most confirmed bookings in 2026 | READ | | | | |
| R22: Support console: all bookings, newest first, page 4,001 (25 per page) | READ | | | | |
| R23: Sign-in with mobile number | READ | | | | |
| R24: Pricing: average price paid per seat class in each city (2026) | READ | | | | |
| R25: Programming: average occupancy of late-night shows (starting 22:30 or later) in June 2026 | READ | | | | |
| W01: Checkout: create a PENDING booking for 2 tickets of show 144446 | WRITE | | | | |
| W02: Seat lock: the oldest PENDING booking adds 2 more seats (the unsold seats with the lowest ids in its show) | WRITE | | | | |
| W03: Payment callback: confirm the oldest PENDING booking | WRITE | | | | |
| W04: Seat-lock expiry: release seats held by PENDING bookings older than 10 minutes | WRITE | | | | |
| W05: Pricing: 10% higher prices for all July weekend shows of movie 2 | WRITE | | | | |
| **Total (sum of all 30)** | | | | | |

Below the table, add for each query the **scan type** from the plan (Seq Scan, Index Scan, …) and one line on **why** it is slow or fast.

---

## Phase 4: Optimize the queries

Make the queries faster. **The results must stay the same** (same rows; order matters only where the query has an `ORDER BY`).

### 4.1 Techniques you may use
| Technique | Example |
|-----------|---------|
| B-tree index (single / composite) | the right column **order** matters: equality columns first, then range/sort |
| Partial index | index only the rows a query needs (e.g. a rare status) |
| Covering index | `INCLUDE (...)` so the table is never visited (Index Only Scan) |
| Expression index | index the exact expression used in `WHERE` |
| GIN index | for `ILIKE '%text%'` (extension `pg_trgm`), arrays or full-text search |
| BRIN index | for huge tables stored in time order |
| Query rewrite | sargable date ranges instead of functions on columns; `NOT EXISTS` instead of `NOT IN`; joins instead of correlated subqueries; keyset instead of `OFFSET` pagination; `UNION ALL` instead of `OR` across columns |
| VACUUM / ANALYZE | fresh statistics and visibility maps |
| Summary table / materialized view | for heavy reports that don't need live data (state how it's refreshed) |

**Not allowed:** changing the data, deleting rows, changing PostgreSQL server settings to hide the problem (e.g. huge `work_mem`, `enable_seqscan = off`), or caching results outside the database.

### 4.2 How to work
1. Put every index in `sql/05_indexes.sql`, each with a comment: **which queries it serves and why this type and column order**.
2. Put rewritten queries in `sql/06_optimized_queries.sql`. Copy `queries/workload_30.sql` and change **only** the queries you rewrite, keeping the `-- @R01` markers.
3. **Prove the results are unchanged** for every rewritten query (compare row counts, plus a checksum or an `EXCEPT` query). Put the proof in your report.
4. Benchmark again with the same method:
```bash
./benchmarks/run_benchmark.sh <your_database> optimized 5 sql/06_optimized_queries.sql
```
> 🔎 **Read the results, not just the timings.** At least one of the 30 original queries returns a **wrong answer** because of a subtle SQL rule about NULLs. Find it, explain it, and fix it. This is worth marks.

### 4.3 Deliverable: the optimization table
In `docs/04_optimization_report.md`:

| Query | Before (ms) | Problem found in the plan | Optimization applied | After (ms) | Improvement | Same result? |
|-------|------------:|---------------------------|----------------------|-----------:|------------:|:------------:|
| R03 | | e.g. Seq Scan on 300k booking_seats | e.g. use the `(show_id, seat_id)` unique index / index on `seats(screen_id)` | | e.g. 99% (90×) | ✅ |
| … all 30 … | | | | | | |
| **Total** | | | | | | |

Improvement % = (before − after) / before × 100

Also include:
- **Before/after `EXPLAIN` plans** for your 5 biggest improvements
- **Write overhead:** which write queries got **slower** because of your indexes, by how much, and whether that's acceptable
- **Index storage:** the size of each index you created (`pg_relation_size`) compared with its table
- **Queries you could not speed up**, and why (an honest "this query must read most of the table" earns marks)

---

## Phase 5: Scalability report (large dataset round)

Your optimizations worked on 300,389 bookings. Next year the business expects **20× the volume**.

By **Thu 19 Nov 2026**, faculty will release **`large_data.zip`**: the same 11 CSV files with about **20× the rows** (≈ 3,201,000 shows, ≈ 3,002,000 bookings, ≈ 6,008,000 booking seats, ≈ 1,881,000 seats, ≈ 800,000 customers). Until then, work on the design part of the report.

### 5.1 What to do with the large dataset
1. Create a new database. Run **your** `01_schema.sql`, load `large_data/` with your load script (change the folder name only), then run **your** `05_indexes.sql` and `ANALYZE`.
2. Run your **optimized** queries (`sql/06_optimized_queries.sql`). **Do not run the original 30 on the large data.** Some of them could run for a very long time.
   - R22 pages with `OFFSET`; if you replaced it with keyset pagination, explain how the "last seen" value is chosen for the large data.
3. Record the times and compare with your Phase 4 results on the seed data.

| Query | Optimized on seed (ms) | Optimized on large (ms) | Growth (large ÷ seed) | Meets target? | If not, what you changed |
|-------|------------------------:|------------------------:|----------------------:|:-------------:|--------------------------|
| R01 | | | | | |
| … all 30 … | | | | | |

### 5.2 Performance targets on the large dataset
| Query group | Queries | Target (average of 3 runs) |
|-------------|---------|----------------:|
| Real-time / booking path | R02, R03, R04, R05, R06, R09, R23, W01, W02, W03 | **under 5 ms** |
| Interactive cinema tools | R01, R07, R13, R17, R22, W04, W05 | **under 250 ms** |
| Reports and analytics | R08, R10, R11, R12, R14, R15, R16, R18, R19, R20, R21, R24, R25 | **under 5,000 ms** |

If a query misses its target, **find out why from the plan and fix it.** A query that was fast on the seed data can become slow on large data for reasons that only appear at scale. Show the before/after plans for every fix.

### 5.3 Deliverable: `docs/05_scalability_report.md`
1. **Results table** (above), with every target met or explained.
2. **Growth analysis.** Group your queries by how their time grew when the data grew 20×:
   - *stayed about the same* (why? e.g. index lookups grow with log n)
   - *grew about 20×* (why? e.g. they read a fixed *share* of the table)
   - *grew more than 20×* (why, and what you did about it)
3. **What broke at scale** and how you fixed it (plans before/after).
4. **Storage:** total database size, table vs index size, on seed and large data.
5. **Architecture for 100×:** explain with numbers from your own measurements:
   - **Partitioning:** which table, by which column (RANGE / LIST / HASH), and why. Write the DDL for `booking_seats`, show partition pruning with `EXPLAIN`, and note the primary-key rule for partitioned tables.
   - **Sharding:** Would you shard by city, by venue, or by show? A booking touches one show at one venue—but box-office reports span all cities. Which queries become cross-shard, and how would you handle them?
   - **Read replicas and caching:** which of the 30 queries you would send to a replica or cache, and which must hit the primary.
   - **Maintenance:** VACUUM/autovacuum settings for `booking_seats`, archiving old data, refreshing summary tables.
6. **Conclusion:** is your database ready for next year? What are the remaining risks?

---

## Repository structure (submit exactly this)

```
bookmyshow-dbms-<team-no>/
├── README.md                          # team table, how to run, headline numbers
├── team.json                          # group lead, members, enrollment numbers
├── docs/
│   ├── 01_problem_understanding.md
│   ├── 02_schema_design.md
│   ├── 03_baseline_timings.md
│   ├── 04_optimization_report.md
│   └── 05_scalability_report.md
├── diagrams/
│   └── er_diagram.png
├── sql/
│   ├── 01_schema.sql
│   ├── 02_load_data.sql
│   ├── 05_indexes.sql
│   ├── 06_optimized_queries.sql
│   └── 08_partitioning.sql
├── queries/
│   └── workload_30.sql                # given; do not edit
└── benchmarks/
    ├── run_benchmark.sh               # given
    └── results/
        ├── baseline/                  # Phase 3: summary.csv + raw plans
        ├── optimized/                 # Phase 4
        └── large/                     # Phase 5
```

`team.json`:
```json
{
  "team_number": "",
  "group_lead": { "name": "", "enrollment_no": "", "github": "" },
  "members": [
    { "name": "", "enrollment_no": "", "github": "" },
    { "name": "", "enrollment_no": "", "github": "" },
    { "name": "", "enrollment_no": "", "github": "" }
  ],
  "postgres_version": "",
  "laptop_used_for_benchmarks": ""
}
```

**Do not commit the CSV files** (`seed_data/`, `large_data/`); add them to `.gitignore`. They are too large and we already have them.

---

## Timeline

| Due | Work | Checkpoint |
|-----|------|------------|
| Tue 3 Nov 2026 | Clone this repo into your team's DE repo, add members, commit `team.json` | **CP0** Setup |
| Mon 16 Nov 2026 | Phase 1 + Phase 2 (schema, load, ER, data dictionary) | **CP1** Schema loads all seed data with no errors |
| Tue 17 Nov 2026 | Phase 3 (baseline, 3 runs, average) + start Phase 4 | **CP2** Baseline table for all 30 queries committed |
| Thu 19 Nov 2026 | Phase 4 (indexes, rewrites, wrong-result query) | **CP3** Optimization table committed |
| Mon 23 Nov 2026 | Phase 5 on the large dataset + final report | **CP4 Final submission:** last commit on the default branch |
| Wed 25 – Thu 26 Nov 2026 | Individual analysis, in class time | **CP5** Individual analysis |

Full list of files per checkpoint, including the AP repo: [`CHECKPOINTS.md`](CHECKPOINTS.md).

---

## Evaluation (40 marks)

These 40 marks are the DE part of the project: **Query Execution (10)** and **Code Optimization (30)**.
The AP project (20) and your Individual analysis (40) make up the rest of the 100.

| Phase | Criteria | Marks |
|-------|----------|------:|
| | **Query Execution** | **10** |
| 1 | Problems understood, stakeholders and query groups correctly identified | 2 |
| 2 | Correct data types (1), keys and foreign keys with justified delete rules (1), ≥12 meaningful CHECK / NOT NULL / UNIQUE constraints (1), ER diagram + normal-form analysis (1), data loads cleanly + integrity checks (1) | 5 |
| 3 | All 30 queries measured with the required method: 3 runs, average (1), raw plans committed (1), scan type and reason for each query (1) | 3 |
| | **Code Optimization** | **30** |
| 4 | Speed-up achieved with appropriate techniques (6), every index justified (3), results proven unchanged (2), wrong-result query found and explained (2), write overhead and index storage reported (3) | 16 |
| 5 | Large-dataset results with all targets met or explained (4), growth analysis (3), scale-only problems found and fixed (3), partitioning DDL + sharding/replica design backed by your numbers (4) | 14 |
| | **Total** | **40** |

**Integrity rules**
- Every number in your reports must match the raw plan files in `benchmarks/results/`. Copied or invented timings make the whole phase score 0.
- Every member must have commits; the commit history is checked.
- You may use AI tools to learn, but you must be able to explain every index and rewrite in your individual analysis.

---

## Appendix: the 30 queries

These are identical to `queries/workload_30.sql`. Use the file, not copy-paste from this page.

**R01: Home page: movies showing in Bengaluru on 2 July 2026 and how many shows each has**
```sql
SELECT m.movie_id, m.title, m.language, m.certificate, count(*) AS shows
FROM shows s
JOIN movies m   ON m.movie_id = s.movie_id
JOIN screens sc ON sc.screen_id = s.screen_id
JOIN venues v   ON v.venue_id = sc.venue_id
WHERE v.city_id = 1
  AND DATE(s.starts_at) = '2026-07-02'
GROUP BY m.movie_id, m.title, m.language, m.certificate
ORDER BY shows DESC;
```

**R02: Showtimes page: shows of movie 2 in Bengaluru on 2 July 2026, grouped by cinema**
```sql
SELECT v.venue_name, sc.screen_type, s.show_id, s.starts_at, s.format, s.base_price
FROM shows s
JOIN screens sc ON sc.screen_id = s.screen_id
JOIN venues v   ON v.venue_id = sc.venue_id
WHERE s.movie_id = 2
  AND v.city_id = 1
  AND s.starts_at >= '2026-07-02' AND s.starts_at < '2026-07-03'
ORDER BY v.venue_name, s.starts_at;
```

**R03: Seat layout: every seat of show 144446 and whether it is already sold**
```sql
SELECT se.row_label, se.seat_number, se.seat_class, (bs.seat_id IS NOT NULL) AS sold
FROM shows s
JOIN seats se ON se.screen_id = s.screen_id
LEFT JOIN booking_seats bs ON bs.show_id = s.show_id AND bs.seat_id = se.seat_id
WHERE s.show_id = 144446
ORDER BY se.row_label DESC, se.seat_number;
```

**R04: Support: open a booking by its code**
```sql
SELECT booking_id, customer_id, show_id, num_tickets, total_amount, status, booked_at
FROM bookings
WHERE booking_code = 'BMSA45E9F9';
```

**R05: "My bookings": customer 1331's upcoming confirmed shows**
```sql
SELECT b.booking_code, m.title, s.starts_at, v.venue_name, b.num_tickets
FROM bookings b
JOIN shows s    ON s.show_id = b.show_id
JOIN movies m   ON m.movie_id = s.movie_id
JOIN screens sc ON sc.screen_id = s.screen_id
JOIN venues v   ON v.venue_id = sc.venue_id
WHERE b.customer_id = 1331 AND b.status = 'CONFIRMED'
  AND s.starts_at >= '2026-07-01'
ORDER BY s.starts_at;
```

**R06: Search: movies whose title contains "kalki"**
```sql
SELECT movie_id, title, language, release_date
FROM movies
WHERE title ILIKE '%kalki%'
ORDER BY release_date DESC;
```

**R07: Cinema dashboard: occupancy of every show at venue 11 on 28 June 2026**
```sql
SELECT s.show_id, sc.screen_name, s.starts_at, count(bs.seat_id) AS sold, sc.total_seats,
       round(100.0 * count(bs.seat_id) / sc.total_seats, 1) AS occupancy_pct
FROM shows s
JOIN screens sc ON sc.screen_id = s.screen_id
LEFT JOIN booking_seats bs ON bs.show_id = s.show_id
WHERE sc.venue_id = 11
  AND s.starts_at::date = '2026-06-28'
GROUP BY s.show_id, sc.screen_name, s.starts_at, sc.total_seats
ORDER BY s.starts_at;
```

**R08: Box office: top 10 movies by collections over the weekend of 26–28 June 2026**
```sql
SELECT m.title, count(DISTINCT b.booking_id) AS bookings, sum(b.ticket_amount) AS collections
FROM bookings b
JOIN shows s  ON s.show_id = b.show_id
JOIN movies m ON m.movie_id = s.movie_id
WHERE b.status = 'CONFIRMED'
  AND s.starts_at >= '2026-06-26' AND s.starts_at < '2026-06-29'
GROUP BY m.title
ORDER BY collections DESC
LIMIT 10;
```

**R09: Seat-lock service: bookings still PENDING more than 10 minutes after they were made (checked at 23:59, 30 Jun 2026)**
```sql
SELECT booking_id, show_id, num_tickets, booked_at
FROM bookings
WHERE status = 'PENDING'
  AND booked_at < TIMESTAMPTZ '2026-06-30 23:59:00+05:30' - interval '10 minutes'
ORDER BY booked_at;
```

**R10: Cinema operations: consecutive shows on the same screen with less than 30 minutes for cleaning (June 2026)**
```sql
SELECT s1.screen_id, s1.show_id, s1.ends_at, s2.show_id AS next_show_id, s2.starts_at,
       s2.starts_at - s1.ends_at AS gap
FROM shows s1
JOIN shows s2 ON s2.screen_id = s1.screen_id
             AND s2.starts_at > s1.starts_at
             AND s2.starts_at - s1.ends_at < interval '30 minutes'
WHERE s1.starts_at >= '2026-06-01' AND s1.starts_at < '2026-07-01'
ORDER BY gap, s1.screen_id;
```

**R11: Revenue mix: share of ticket revenue from recliner seats, per screen type**
```sql
SELECT sc.screen_type, sum(bs.price) AS revenue,
       round(100.0 * sum(bs.price) FILTER (WHERE se.seat_class = 'RECLINER') / sum(bs.price), 1) AS recliner_pct
FROM booking_seats bs
JOIN seats se   ON se.seat_id = bs.seat_id
JOIN screens sc ON sc.screen_id = se.screen_id
GROUP BY sc.screen_type
ORDER BY revenue DESC;
```

**R12: Fans: customers who booked the same movie more than once**
```sql
SELECT b.customer_id, s.movie_id, count(*) AS times_booked
FROM bookings b
JOIN shows s ON s.show_id = b.show_id
WHERE b.status = 'CONFIRMED'
GROUP BY b.customer_id, s.movie_id
HAVING count(*) > 1
ORDER BY times_booked DESC, b.customer_id;
```

**R13: Partnerships: offers that have never been redeemed**
```sql
SELECT o.offer_code, o.description, o.discount_pct
FROM offers o
WHERE o.offer_code NOT IN (SELECT b.offer_code FROM bookings b);
```

**R14: Movie pages: average user rating of 2026 releases with at least 20 reviews**
```sql
SELECT m.movie_id, m.title, round(avg(r.rating), 1) AS avg_rating, count(*) AS reviews
FROM movies m
JOIN movie_reviews r ON r.movie_id = m.movie_id
WHERE m.release_date >= '2026-01-01'
GROUP BY m.movie_id, m.title
HAVING count(*) >= 20
ORDER BY avg_rating DESC
LIMIT 20;
```

**R15: Capacity planning: bookings by weekday and hour of booking**
```sql
SELECT EXTRACT(ISODOW FROM booked_at) AS weekday, EXTRACT(HOUR FROM booked_at) AS hour, count(*) AS bookings
FROM bookings
GROUP BY 1, 2
ORDER BY 1, 2;
```

**R16: Cinema partners: cancellation rate per venue for June 2026 shows**
```sql
SELECT v.venue_id, v.venue_name, count(*) AS bookings,
       round(100.0 * count(*) FILTER (WHERE b.status = 'CANCELLED') / count(*), 2) AS cancel_pct
FROM bookings b
JOIN shows s    ON s.show_id = b.show_id
JOIN screens sc ON sc.screen_id = s.screen_id
JOIN venues v   ON v.venue_id = sc.venue_id
WHERE s.starts_at >= '2026-06-01' AND s.starts_at < '2026-07-01'
GROUP BY v.venue_id, v.venue_name
ORDER BY cancel_pct DESC;
```

**R17: Cinema operations: seats of screen 101 that were never sold for any June 2026 show**
```sql
SELECT se.seat_id, se.row_label, se.seat_number, se.seat_class
FROM seats se
WHERE se.screen_id = 101
  AND NOT EXISTS (SELECT 1 FROM booking_seats bs JOIN shows s ON s.show_id = bs.show_id
                  WHERE bs.seat_id = se.seat_id
                    AND s.starts_at >= '2026-06-01' AND s.starts_at < '2026-07-01')
ORDER BY se.row_label, se.seat_number;
```

**R18: Regional insights: collections per language per city in 2026**
```sql
SELECT v.city_id, m.language, sum(b.ticket_amount) AS collections
FROM bookings b
JOIN shows s    ON s.show_id = b.show_id
JOIN movies m   ON m.movie_id = s.movie_id
JOIN screens sc ON sc.screen_id = s.screen_id
JOIN venues v   ON v.venue_id = sc.venue_id
WHERE b.status = 'CONFIRMED'
  AND EXTRACT(YEAR FROM s.starts_at) = 2026
GROUP BY v.city_id, m.language
ORDER BY v.city_id, collections DESC;
```

**R19: Distributor report: tickets sold for every June 2026 show of movie 2**
```sql
SELECT s.show_id, s.starts_at, s.screen_id,
       (SELECT coalesce(sum(b.num_tickets), 0) FROM bookings b
         WHERE b.show_id = s.show_id AND b.status = 'CONFIRMED') AS tickets_sold
FROM shows s
WHERE s.movie_id = 2
  AND s.starts_at >= '2026-06-01' AND s.starts_at < '2026-07-01'
ORDER BY tickets_sold DESC, s.starts_at;
```

**R20: Finance: daily collections and running total for June 2026**
```sql
SELECT day, collections, sum(collections) OVER (ORDER BY day) AS running_total
FROM (
    SELECT booked_at::date AS day, sum(total_amount) AS collections
    FROM bookings
    WHERE status = 'CONFIRMED'
      AND booked_at::date BETWEEN '2026-06-01' AND '2026-06-30'
    GROUP BY 1
) d
ORDER BY day;
```

**R21: Loyalty: 20 customers with the most confirmed bookings in 2026**
```sql
SELECT customer_id, count(*) AS bookings, sum(total_amount) AS spend
FROM bookings
WHERE status = 'CONFIRMED' AND booked_at >= '2026-01-01'
GROUP BY customer_id
ORDER BY bookings DESC, spend DESC
LIMIT 20;
```

**R22: Support console: all bookings, newest first, page 4,001 (25 per page)**
```sql
SELECT booking_id, booking_code, customer_id, show_id, status, booked_at
FROM bookings
ORDER BY booked_at DESC
OFFSET 100000
LIMIT 25;
```

**R23: Sign-in with mobile number**
```sql
SELECT customer_id, full_name, city_id
FROM customers
WHERE phone = '7700001331';
```

**R24: Pricing: average price paid per seat class in each city (2026)**
```sql
SELECT v.city_id, se.seat_class, round(avg(bs.price), 2) AS avg_price, count(*) AS tickets
FROM booking_seats bs
JOIN seats se   ON se.seat_id = bs.seat_id
JOIN screens sc ON sc.screen_id = se.screen_id
JOIN venues v   ON v.venue_id = sc.venue_id
GROUP BY v.city_id, se.seat_class
ORDER BY v.city_id, se.seat_class;
```

**R25: Programming: average occupancy of late-night shows (starting 22:30 or later) in June 2026**
```sql
SELECT s.show_id, s.starts_at, sc.total_seats, count(bs.seat_id) AS sold
FROM shows s
JOIN screens sc ON sc.screen_id = s.screen_id
LEFT JOIN booking_seats bs ON bs.show_id = s.show_id
WHERE s.starts_at::time >= '22:30'
  AND s.starts_at >= '2026-06-01' AND s.starts_at < '2026-07-01'
GROUP BY s.show_id, s.starts_at, sc.total_seats
ORDER BY sold DESC
LIMIT 50;
```

**W01: Checkout: create a PENDING booking for 2 tickets of show 144446**
```sql
INSERT INTO bookings (booking_id, booking_code, customer_id, show_id, booked_at, num_tickets, ticket_amount,
                      convenience_fee, fnb_amount, discount, total_amount, payment_method, status)
VALUES (90000001, 'BMS0FFFFFF', 1331, 144446, '2026-06-28 10:00:00+05:30', 2, 500.00, 50.00, 0, 0, 550.00, 'UPI', 'PENDING');
```

**W02: Seat lock: the oldest PENDING booking adds 2 more seats (the unsold seats with the lowest ids in its show)**
```sql
INSERT INTO booking_seats (booking_id, show_id, seat_id, price)
SELECT b.booking_id, b.show_id, se.seat_id, 250.00
FROM bookings b
JOIN shows s  ON s.show_id = b.show_id
JOIN seats se ON se.screen_id = s.screen_id
WHERE b.booking_id = (SELECT min(booking_id) FROM bookings WHERE status = 'PENDING')
  AND NOT EXISTS (SELECT 1 FROM booking_seats bs WHERE bs.show_id = b.show_id AND bs.seat_id = se.seat_id)
ORDER BY se.seat_id
LIMIT 2
ON CONFLICT (show_id, seat_id) DO NOTHING;
```

**W03: Payment callback: confirm the oldest PENDING booking**
```sql
UPDATE bookings
SET status = 'CONFIRMED'
WHERE booking_id = (SELECT min(booking_id) FROM bookings WHERE status = 'PENDING');
```

**W04: Seat-lock expiry: release seats held by PENDING bookings older than 10 minutes**
```sql
DELETE FROM booking_seats bs
USING bookings b
WHERE b.booking_id = bs.booking_id
  AND b.status = 'PENDING'
  AND b.booked_at < TIMESTAMPTZ '2026-06-30 23:59:00+05:30' - interval '10 minutes';
```

**W05: Pricing: 10% higher prices for all July weekend shows of movie 2**
```sql
UPDATE shows
SET base_price = round(base_price * 1.10, 0)
WHERE movie_id = 2
  AND starts_at >= '2026-07-01'
  AND EXTRACT(ISODOW FROM starts_at) IN (6, 7);
```
