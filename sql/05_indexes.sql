-- =====================================================================
-- BookMyShow DBMS Project - Phase 4: Secondary Indexes
-- Schema: bms
-- Team: T0132
-- Description:
--   Secondary B-Tree, GIN, and Partial indexes for query optimization.
-- =====================================================================

SET search_path TO bms;

-- 1. Enable Trigram Extension for Text Search
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

-- 3. Movie Title Search (GIN Trigram index for ILIKE '%text%')
-- Upgraded from standard B-Tree to GIN trigram index to accelerate wildcard search (R06)
DROP INDEX IF EXISTS idx_movies_title;
CREATE INDEX IF NOT EXISTS idx_movies_title_trgm ON movies USING gin (title gin_trgm_ops);

-- 4. Show Scheduling & Gap Analysis (R10)
-- Ordered (screen_id, starts_at, ends_at) so self-joins can perform an index scan per screen
DROP INDEX IF EXISTS idx_shows_starts_screen;
CREATE INDEX IF NOT EXISTS idx_shows_movie_starts ON shows (movie_id, starts_at);
CREATE INDEX IF NOT EXISTS idx_shows_screen_starts_ends ON shows (screen_id, starts_at, ends_at);

-- 5. Customer Bookings Filtering
CREATE INDEX IF NOT EXISTS idx_bookings_cust_status ON bookings (customer_id, status);
CREATE INDEX IF NOT EXISTS idx_bookings_status_date ON bookings (status, booked_at);

-- 6. Partial Index for Pending Bookings (W02, W03, R09)
CREATE INDEX IF NOT EXISTS idx_bookings_pending_id ON bookings (booking_id) WHERE status = 'PENDING';
