-- =====================================================================
-- BookMyShow DBMS Project - Phase 5: Large Dataset Ingestion & Verification
-- Schema: bms
-- Authors: Team T0132
-- Description:
--   Automated data loader utilizing PostgreSQL \copy command in strict
--   topological dependency order for the official 20x large dataset.
-- =====================================================================

SET search_path TO bms;

\echo '==> [1/11] Ingesting cities.csv...'
\copy cities (city_id, city_name, state) FROM 'large_data/cities.csv' WITH (FORMAT csv, HEADER true);

\echo '==> [2/11] Ingesting venues.csv...'
\copy venues (venue_id, venue_name, city_id, chain, address) FROM 'large_data/venues.csv' WITH (FORMAT csv, HEADER true);

\echo '==> [3/11] Ingesting screens.csv...'
\copy screens (screen_id, venue_id, screen_name, screen_type, total_seats) FROM 'large_data/screens.csv' WITH (FORMAT csv, HEADER true);

\echo '==> [4/11] Ingesting seats.csv...'
\copy seats (seat_id, screen_id, row_label, seat_number, seat_class) FROM 'large_data/seats.csv' WITH (FORMAT csv, HEADER true);

\echo '==> [5/11] Ingesting movies.csv...'
\copy movies (movie_id, title, language, certificate, duration_min, release_date) FROM 'large_data/movies.csv' WITH (FORMAT csv, HEADER true);

\echo '==> [6/11] Ingesting shows.csv...'
\copy shows (show_id, movie_id, screen_id, starts_at, ends_at, format, base_price) FROM 'large_data/shows.csv' WITH (FORMAT csv, HEADER true);

\echo '==> [7/11] Ingesting customers.csv...'
\copy customers (customer_id, full_name, email, phone, city_id, created_at) FROM 'large_data/customers.csv' WITH (FORMAT csv, HEADER true);

\echo '==> [8/11] Ingesting offers.csv...'
\copy offers (offer_code, description, discount_pct, max_discount, valid_from, valid_to) FROM 'large_data/offers.csv' WITH (FORMAT csv, HEADER true);

\echo '==> [9/11] Ingesting bookings.csv...'
\copy bookings (booking_id, booking_code, customer_id, show_id, booked_at, num_tickets, ticket_amount, convenience_fee, fnb_amount, offer_code, discount, total_amount, payment_method, status) FROM 'large_data/bookings.csv' WITH (FORMAT csv, HEADER true);

\echo '==> [10/11] Ingesting booking_seats.csv...'
\copy booking_seats (booking_id, show_id, seat_id, price) FROM 'large_data/booking_seats.csv' WITH (FORMAT csv, HEADER true);

\echo '==> [11/11] Ingesting movie_reviews.csv...'
\copy movie_reviews (review_id, movie_id, customer_id, rating, review_text, created_at) FROM 'large_data/movie_reviews.csv' WITH (FORMAT csv, HEADER true);

\echo '==> Updating database statistics (ANALYZE)...'
ANALYZE;

\echo '==> Verification: Validating exact row counts across all 11 tables...'
SELECT 'cities' AS table_name, count(*) AS actual_rows, 10 AS expected_rows, (count(*) = 10) AS matches FROM cities
UNION ALL
SELECT 'venues', count(*), 2800, (count(*) = 2800) FROM venues
UNION ALL
SELECT 'screens', count(*), 9800, (count(*) = 9800) FROM screens
UNION ALL
SELECT 'seats', count(*), 1879182, (count(*) = 1879182) FROM seats
UNION ALL
SELECT 'movies', count(*), 6000, (count(*) = 6000) FROM movies
UNION ALL
SELECT 'shows', count(*), 3201268, (count(*) = 3201268) FROM shows
UNION ALL
SELECT 'customers', count(*), 800000, (count(*) = 800000) FROM customers
UNION ALL
SELECT 'offers', count(*), 25, (count(*) = 25) FROM offers
UNION ALL
SELECT 'bookings', count(*), 3004077, (count(*) = 3004077) FROM bookings
UNION ALL
SELECT 'booking_seats', count(*), 6016946, (count(*) = 6016946) FROM booking_seats
UNION ALL
SELECT 'movie_reviews', count(*), 651398, (count(*) = 651398) FROM movie_reviews;
