-- =====================================================================
-- BookMyShow DBMS Project - Phase 2: Seed Data Ingestion & Verification
-- Schema: bms
-- Authors: Team T0132
-- Description:
--   Automated data loader utilizing PostgreSQL \copy command in strict
--   topological dependency order (parents prior to dependent children).
--   Executes post-load ANALYZE and performs 5 thorough relational integrity
--   and business rule validation queries.
--
-- EXECUTION:
--   psql -d <database_name> -f sql/02_load_data.sql
--   (Ensure execution from project root directory where seed_data/ resides)
-- =====================================================================

SET search_path TO bms;

\echo '==> [1/11] Ingesting cities.csv...'
\copy cities (city_id, city_name, state) FROM 'seed_data/cities.csv' WITH (FORMAT csv, HEADER true);

\echo '==> [2/11] Ingesting venues.csv...'
\copy venues (venue_id, venue_name, city_id, chain, address) FROM 'seed_data/venues.csv' WITH (FORMAT csv, HEADER true);

\echo '==> [3/11] Ingesting screens.csv...'
\copy screens (screen_id, venue_id, screen_name, screen_type, total_seats) FROM 'seed_data/screens.csv' WITH (FORMAT csv, HEADER true);

\echo '==> [4/11] Ingesting seats.csv...'
\copy seats (seat_id, screen_id, row_label, seat_number, seat_class) FROM 'seed_data/seats.csv' WITH (FORMAT csv, HEADER true);

\echo '==> [5/11] Ingesting movies.csv...'
\copy movies (movie_id, title, language, certificate, duration_min, release_date) FROM 'seed_data/movies.csv' WITH (FORMAT csv, HEADER true);

\echo '==> [6/11] Ingesting shows.csv...'
\copy shows (show_id, movie_id, screen_id, starts_at, ends_at, format, base_price) FROM 'seed_data/shows.csv' WITH (FORMAT csv, HEADER true);

\echo '==> [7/11] Ingesting customers.csv...'
\copy customers (customer_id, full_name, email, phone, city_id, created_at) FROM 'seed_data/customers.csv' WITH (FORMAT csv, HEADER true);

\echo '==> [8/11] Ingesting offers.csv...'
\copy offers (offer_code, description, discount_pct, max_discount, valid_from, valid_to) FROM 'seed_data/offers.csv' WITH (FORMAT csv, HEADER true);

\echo '==> [9/11] Ingesting bookings.csv...'
\copy bookings (booking_id, booking_code, customer_id, show_id, booked_at, num_tickets, ticket_amount, convenience_fee, fnb_amount, offer_code, discount, total_amount, payment_method, status) FROM 'seed_data/bookings.csv' WITH (FORMAT csv, HEADER true);

\echo '==> [10/11] Ingesting booking_seats.csv...'
\copy booking_seats (booking_id, show_id, seat_id, price) FROM 'seed_data/booking_seats.csv' WITH (FORMAT csv, HEADER true);

\echo '==> [11/11] Ingesting movie_reviews.csv...'
\copy movie_reviews (review_id, movie_id, customer_id, rating, review_text, created_at) FROM 'seed_data/movie_reviews.csv' WITH (FORMAT csv, HEADER true);

\echo '==> Updating database statistics (ANALYZE)...'
ANALYZE;

-- =====================================================================
-- POST-INGESTION VERIFICATION & RELATIONAL AUDIT
-- =====================================================================

\echo '==> Verification 1: Validating exact row counts across all 11 tables...'
SELECT 'cities' AS table_name, count(*) AS actual_rows, 10 AS expected_rows, (count(*) = 10) AS matches FROM cities
UNION ALL
SELECT 'venues', count(*), 140, (count(*) = 140) FROM venues
UNION ALL
SELECT 'screens', count(*), 490, (count(*) = 490) FROM screens
UNION ALL
SELECT 'seats', count(*), 94056, (count(*) = 94056) FROM seats
UNION ALL
SELECT 'movies', count(*), 300, (count(*) = 300) FROM movies
UNION ALL
SELECT 'shows', count(*), 160034, (count(*) = 160034) FROM shows
UNION ALL
SELECT 'customers', count(*), 40000, (count(*) = 40000) FROM customers
UNION ALL
SELECT 'offers', count(*), 25, (count(*) = 25) FROM offers
UNION ALL
SELECT 'bookings', count(*), 150094, (count(*) = 150094) FROM bookings
UNION ALL
SELECT 'booking_seats', count(*), 300389, (count(*) = 300389) FROM booking_seats
UNION ALL
SELECT 'movie_reviews', count(*), 32510, (count(*) = 32510) FROM movie_reviews;

\echo '==> Integrity Check 1: Verifying every booked seat belongs to the screen hosting the show...'
SELECT count(*) AS invalid_screen_seat_mappings
FROM booking_seats bs
JOIN shows s  ON s.show_id = bs.show_id
JOIN seats se ON se.seat_id = bs.seat_id
WHERE s.screen_id <> se.screen_id;

\echo '==> Integrity Check 2: Verifying num_tickets strictly equals seats held for active bookings...'
SELECT count(*) AS ticket_seat_count_mismatches
FROM bookings b
LEFT JOIN (
    SELECT booking_id, count(*) AS actual_seats
    FROM booking_seats
    GROUP BY booking_id
) bs ON bs.booking_id = b.booking_id
WHERE (b.status IN ('CONFIRMED', 'PENDING') AND b.num_tickets <> coalesce(bs.actual_seats, 0))
   OR (b.status IN ('CANCELLED', 'PAYMENT_FAILED') AND coalesce(bs.actual_seats, 0) <> 0);

\echo '==> Integrity Check 3: Confirming total_seats on screens matches exact count of physical seats...'
SELECT count(*) AS screen_capacity_discrepancies
FROM screens sc
JOIN (
    SELECT screen_id, count(*) AS physical_seats
    FROM seats
    GROUP BY screen_id
) se ON se.screen_id = sc.screen_id
WHERE sc.total_seats <> se.physical_seats;

\echo '==> Integrity Check 4: Verifying no two shows overlap in schedule on any screen...'
SELECT count(*) AS overlapping_show_pairs
FROM shows s1
JOIN shows s2 ON s1.screen_id = s2.screen_id 
             AND s1.show_id < s2.show_id
             AND tstzrange(s1.starts_at, s1.ends_at) && tstzrange(s2.starts_at, s2.ends_at);

\echo '==> Integrity Check 5: Financial audit confirming ticket_amount equals sum of booking_seats.price...'
SELECT count(*) AS booking_seat_price_mismatches
FROM bookings b
JOIN (
    SELECT booking_id, round(sum(price), 2) AS seat_price_sum
    FROM booking_seats
    GROUP BY booking_id
) bs ON bs.booking_id = b.booking_id
WHERE b.status IN ('CONFIRMED', 'PENDING')
  AND b.ticket_amount <> bs.seat_price_sum;

\echo '==> Data loading and integrity verification completed successfully!'
