-- =====================================================================
-- BookMyShow DBMS Project - Phase 4: Secondary Indexes
-- Schema: bms
-- Team: T0132
-- Description:
--   Comprehensive secondary B-Tree, GIN, Covering, and Partial indexes
--   targeting workload_30 performance bottlenecks.
-- =====================================================================

SET search_path TO bms;

-- 1. Text Search Trigram Extension (R06)
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- 2. Foreign Key Join Indexes
CREATE INDEX IF NOT EXISTS idx_venues_city_id ON venues (city_id);
CREATE INDEX IF NOT EXISTS idx_screens_venue_id ON screens (venue_id);
CREATE INDEX IF NOT EXISTS idx_seats_screen_id ON seats (screen_id);
CREATE INDEX IF NOT EXISTS idx_shows_movie_id ON shows (movie_id);
CREATE INDEX IF NOT EXISTS idx_shows_screen_id ON shows (screen_id);
CREATE INDEX IF NOT EXISTS idx_bookings_customer_id ON bookings (customer_id);
CREATE INDEX IF NOT EXISTS idx_bookings_show_id ON bookings (show_id);
CREATE INDEX IF NOT EXISTS idx_booking_seats_booking_id ON booking_seats (booking_id);
CREATE INDEX IF NOT EXISTS idx_booking_seats_seat_id ON booking_seats (seat_id);
CREATE INDEX IF NOT EXISTS idx_movie_reviews_movie_id ON movie_reviews (movie_id);

-- 3. Movie Title Substring Search (R06)
DROP INDEX IF EXISTS idx_movies_title;
CREATE INDEX IF NOT EXISTS idx_movies_title_trgm ON movies USING gin (title gin_trgm_ops);

-- 4. Show Scheduling & Gap Analysis (R02, R10, R19, R25, W05)
DROP INDEX IF EXISTS idx_shows_starts_screen;
CREATE INDEX IF NOT EXISTS idx_shows_movie_starts ON shows (movie_id, starts_at);
CREATE INDEX IF NOT EXISTS idx_shows_screen_starts_ends ON shows (screen_id, starts_at, ends_at);
CREATE INDEX IF NOT EXISTS idx_shows_starts_at ON shows (starts_at);

-- 5. Customer Bookings Filtering (R05)
CREATE INDEX IF NOT EXISTS idx_bookings_cust_status ON bookings (customer_id, status);
CREATE INDEX IF NOT EXISTS idx_bookings_status_date ON bookings (status, booked_at);

-- 6. Partial Indexes for Targeted Status Queues
-- Fast-path lookup for oldest pending booking (W02, W03)
CREATE INDEX IF NOT EXISTS idx_bookings_pending_id ON bookings (booking_id) WHERE status = 'PENDING';
-- Expiry cleanup daemon for stale pending reservations (R09, W04)
CREATE INDEX IF NOT EXISTS idx_bookings_pending_booked_at ON bookings (booked_at) WHERE status = 'PENDING';
-- Financial analytics on confirmed orders (R08, R20, R21)
CREATE INDEX IF NOT EXISTS idx_bookings_confirmed_booked_at ON bookings (booked_at) WHERE status = 'CONFIRMED';

-- 7. Indexed Sorting for Deep Pagination (R22)
CREATE INDEX IF NOT EXISTS idx_bookings_booked_at_desc ON bookings (booked_at DESC, booking_id DESC);

-- 8. Covering Index for Seat Revenue Mix (R11, R24)
CREATE INDEX IF NOT EXISTS idx_seats_covering ON seats (seat_id) INCLUDE (screen_id, seat_class);
