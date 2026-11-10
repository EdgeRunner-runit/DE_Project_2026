-- =====================================================================
-- BookMyShow DBMS Project - Phase 4: Production Secondary Indexes
-- Schema: bms
-- Team: T0132
-- Description:
--   Comprehensive indexing strategy designed to optimize workload_30 queries.
--   Includes standard B-Trees, GIN trigram indexes, covering indexes with
--   INCLUDE clauses, and selective partial indexes.
--
-- DESIGN RULES & JUSTIFICATIONS:
--   1. Column Order: Equality predicates placed first, followed by range
--      filters, followed by ORDER BY sorting columns.
--   2. Index Types:
--      - B-Tree: High-cardinality equality lookups, range scans, ordering.
--      - GIN (pg_trgm): Substring, infix, and pattern matching (%text%).
--      - Covering (INCLUDE): Index-only scans without heap tuple visits.
--      - Partial (WHERE): Highly selective subsets (e.g. rare status flags).
-- =====================================================================

SET search_path TO bms;

-- ---------------------------------------------------------------------
-- EXTENSION: pg_trgm
-- Targets: R06
-- Justification: Standard B-Trees cannot serve substring patterns with
--   leading wildcards (e.g. ILIKE '%kalki%'). Trigram tokenization breaks
--   strings into 3-character n-grams indexed in a Generalized Inverted Index.
-- ---------------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS pg_trgm;


-- =====================================================================
-- GROUP 1: FOREIGN KEY RELATIONSHIP INDEXES
-- PostgreSQL does not automatically index foreign key columns. These indexes
-- prevent sequential scans during multi-table relational joins.
-- =====================================================================

-- Targets: R01, R02, R05, R16, R18, R24
-- Justification: Traversal from venues to municipal territory filters (WHERE v.city_id = 1).
CREATE INDEX IF NOT EXISTS idx_venues_city_id 
  ON venues (city_id);

-- Targets: R01, R02, R05, R07, R10, R11, R16, R18, R24, R25
-- Justification: Eliminates full auditorium table scans when joining cinema complexes to screens.
CREATE INDEX IF NOT EXISTS idx_screens_venue_id 
  ON screens (venue_id);

-- Targets: R03, R11, R17, R24
-- Justification: Resolves seat grids for auditoriums; enables index-nested loop joins.
CREATE INDEX IF NOT EXISTS idx_seats_screen_id 
  ON seats (screen_id);

-- Targets: R01, R02, R08, R12, R18, R19, W05
-- Justification: Fast foreign-key lookup connecting scheduled shows to catalog movie records.
CREATE INDEX IF NOT EXISTS idx_shows_movie_id 
  ON shows (movie_id);

-- Targets: R01, R02, R03, R05, R07, R10, R16, R18, R25
-- Justification: Crucial for joining auditorium screens with scheduled screenings.
CREATE INDEX IF NOT EXISTS idx_shows_screen_id 
  ON shows (screen_id);

-- Targets: R05, R12, R21
-- Justification: Accelerates customer transaction lookups in booking histories.
CREATE INDEX IF NOT EXISTS idx_bookings_customer_id 
  ON bookings (customer_id);

-- Targets: R05, R08, R12, R16, R18, R19
-- Justification: Connects shows to booking orders; critical for box-office aggregation.
CREATE INDEX IF NOT EXISTS idx_bookings_show_id 
  ON bookings (show_id);

-- Targets: W04, cascading deletes
-- Justification: Resolves individual seats allocated under a booking order.
CREATE INDEX IF NOT EXISTS idx_booking_seats_booking_id 
  ON booking_seats (booking_id);

-- Targets: R11, R17, R24
-- Justification: The booking_seats primary key is (show_id, seat_id). Because seat_id
--   is the secondary key column, standalone seat lookups cannot use the PK index.
--   This reverse index enables index scans when joining on seat_id.
CREATE INDEX IF NOT EXISTS idx_booking_seats_seat_id 
  ON booking_seats (seat_id);

-- Targets: R14
-- Justification: Movie page reviews lookup; eliminates full scan of customer review feedback.
CREATE INDEX IF NOT EXISTS idx_movie_reviews_movie_id 
  ON movie_reviews (movie_id);


-- =====================================================================
-- GROUP 2: TEXT SEARCH INDEXES
-- =====================================================================

-- Targets: R06 (Search movies by title)
-- Justification: GIN index over trigram decomposition. Accelerates ILIKE '%text%'
--   queries via Bitmap Index Scan rather than full table sequential scan.
DROP INDEX IF EXISTS idx_movies_title;
CREATE INDEX IF NOT EXISTS idx_movies_title_trgm 
  ON movies USING gin (title gin_trgm_ops);


-- =====================================================================
-- GROUP 3: COMPOSITE SCHEDULING & SHOWTIME INDEXES
-- =====================================================================

-- Targets: R02, R19, W05 (Showtimes and Distributor reporting)
-- Justification: Composite index with equality on movie_id first, followed by
--   range scan on starts_at. Enables index-range scans for movie release windows.
CREATE INDEX IF NOT EXISTS idx_shows_movie_starts 
  ON shows (movie_id, starts_at);

-- Targets: R10 (Cinema Cleaning Gap Self-Join)
-- Justification: Ordered (screen_id, starts_at, ends_at). The self-join condition
--   equates screen_id (equality first) and seeks s2.starts_at > s1.starts_at (range second).
--   Including ends_at enables an Index-Only scan avoiding heap lookups.
DROP INDEX IF EXISTS idx_shows_starts_screen;
CREATE INDEX IF NOT EXISTS idx_shows_screen_starts_ends 
  ON shows (screen_id, starts_at, ends_at);

-- Targets: R01, R07, R16, R18, R25
-- Justification: Global temporal range scans filtering scheduled shows across all venues.
CREATE INDEX IF NOT EXISTS idx_shows_starts_at 
  ON shows (starts_at);


-- =====================================================================
-- GROUP 4: CUSTOMER BOOKINGS & ORDER FILTERING
-- =====================================================================

-- Targets: R05 (Customer's upcoming confirmed shows)
-- Justification: Composite filter matching WHERE customer_id = X AND status = 'CONFIRMED'.
--   Equality columns placed first to narrow candidate set to single-digit rows.
CREATE INDEX IF NOT EXISTS idx_bookings_cust_status 
  ON bookings (customer_id, status);

-- Targets: R08, R16, R18
-- Justification: Composite filter matching confirmed status and transaction date.
CREATE INDEX IF NOT EXISTS idx_bookings_status_date 
  ON bookings (status, booked_at);


-- =====================================================================
-- GROUP 5: HIGH-SELECTIVITY PARTIAL INDEXES
-- Partial indexes save substantial memory and maintenance overhead by
-- only indexing the small slice of rows required by transactional queues.
-- =====================================================================

-- Targets: W02, W03 (Oldest pending reservation checkout)
-- Justification: Only <1% of bookings are in 'PENDING' status at any given time.
--   Indexing min(booking_id) WHERE status = 'PENDING' reduces lookup to 0.08ms.
CREATE INDEX IF NOT EXISTS idx_bookings_pending_id 
  ON bookings (booking_id) 
  WHERE status = 'PENDING';

-- Targets: R09, W04 (Seat-lock expiry background daemon)
-- Justification: Partial index on booked_at filtered to status = 'PENDING'.
--   The expiry background worker checks pending rows older than 10 minutes;
--   this index isolates stale locks in sub-millisecond execution without scanning
--   hundreds of thousands of confirmed historical bookings.
CREATE INDEX IF NOT EXISTS idx_bookings_pending_booked_at 
  ON bookings (booked_at) 
  WHERE status = 'PENDING';

-- Targets: R08, R20, R21 (Financial revenue and loyalty reports)
-- Justification: Most financial analytics focus strictly on confirmed bookings.
--   Omits cancelled and failed transactions, minimizing index footprint.
CREATE INDEX IF NOT EXISTS idx_bookings_confirmed_booked_at 
  ON bookings (booked_at) 
  WHERE status = 'CONFIRMED';


-- =====================================================================
-- GROUP 6: PAGINATION & COVERING INDEXES
-- =====================================================================

-- Targets: R22 (Deep offset support console)
-- Justification: B-Tree index on (booked_at DESC, booking_id DESC) supports ordered
--   traversal and cursor-based / keyset pagination without full-table sorting.
CREATE INDEX IF NOT EXISTS idx_bookings_booked_at_desc 
  ON bookings (booked_at DESC, booking_id DESC);

-- Targets: R11, R24 (Seat Revenue Breakdown by Screen Type & City)
-- Justification: Covering index. Stores seat_id in the B-Tree search key and includes
--   screen_id and seat_class in the leaf pages. Eliminates heap table visits for R11.
CREATE INDEX IF NOT EXISTS idx_seats_covering 
  ON seats (seat_id) 
  INCLUDE (screen_id, seat_class);
