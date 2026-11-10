-- =====================================================================
-- BookMyShow DBMS Project - Phase 4: Secondary Indexes
-- Schema: bms
-- Team: T0132
-- Description:
--   Draft of secondary B-Tree indexes targeting foreign key joins,
--   date range lookups, and customer filtering.
-- =====================================================================

SET search_path TO bms;

-- 1. Foreign Key Join Indexes
CREATE INDEX IF NOT EXISTS idx_venues_city_id ON venues (city_id);
CREATE INDEX IF NOT EXISTS idx_screens_venue_id ON screens (venue_id);
CREATE INDEX IF NOT EXISTS idx_seats_screen_id ON seats (screen_id);
CREATE INDEX IF NOT EXISTS idx_shows_movie_id ON shows (movie_id);
CREATE INDEX IF NOT EXISTS idx_shows_screen_id ON shows (screen_id);
CREATE INDEX IF NOT EXISTS idx_bookings_customer_id ON bookings (customer_id);
CREATE INDEX IF NOT EXISTS idx_bookings_show_id ON bookings (show_id);
CREATE INDEX IF NOT EXISTS idx_booking_seats_booking_id ON booking_seats (booking_id);

-- 2. Movie Title Search (Initial draft B-Tree)
CREATE INDEX IF NOT EXISTS idx_movies_title ON movies (title);

-- 3. Show Date Ranges & Filtering
CREATE INDEX IF NOT EXISTS idx_shows_movie_starts ON shows (movie_id, starts_at);
CREATE INDEX IF NOT EXISTS idx_shows_starts_screen ON shows (starts_at, screen_id);

-- 4. Customer Bookings Filtering
CREATE INDEX IF NOT EXISTS idx_bookings_cust_status ON bookings (customer_id, status);
CREATE INDEX IF NOT EXISTS idx_bookings_status_date ON bookings (status, booked_at);
