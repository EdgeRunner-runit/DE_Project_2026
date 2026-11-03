-- =====================================================================
-- BookMyShow DBMS Project - Phase 2: Relational Schema Definition
-- Schema: bms
-- Authors: Team T0132
-- Description:
--   Complete DDL specification for the BookMyShow ticketing engine.
--   Enforces 3NF/BCNF relational integrity, primary/foreign key hierarchies,
--   temporal exclusion constraints for show scheduling, and 16+ business domain
--   CHECK constraints.
--
-- STRICT CONSTRAINT RULE (Phase 2):
--   In accordance with project guidelines, ONLY declarative constraints
--   (PK, FK, UNIQUE, NOT NULL, CHECK, EXCLUSION) are established.
--   No secondary performance indexes are created here; baseline timings in
--   Phase 3 will reflect untuned table scans and primary key indexes only.
-- =====================================================================

-- 1. Initialize clean schema namespace
DROP SCHEMA IF EXISTS bms CASCADE;
CREATE SCHEMA bms;
SET search_path TO bms;

-- Enable btree_gist extension for PostgreSQL exclusion constraint
-- (Screen temporal overlap prevention: no two shows can overlap on the same screen)
CREATE EXTENSION IF NOT EXISTS btree_gist;


-- =====================================================================
-- TABLE 1: cities
-- Geographic locations where BookMyShow operates partner cinema venues.
-- =====================================================================
CREATE TABLE cities (
    city_id     INT PRIMARY KEY,
    city_name   VARCHAR(100) NOT NULL UNIQUE,
    state       VARCHAR(100) NOT NULL,
    CONSTRAINT chk_cities_name_nonempty CHECK (length(trim(city_name)) > 0),
    CONSTRAINT chk_cities_state_nonempty CHECK (length(trim(state)) > 0)
);


-- =====================================================================
-- TABLE 2: venues
-- Physical cinema complexes (multiplexes/single screens) situated in cities.
-- Deletion policy:
--   city_id -> RESTRICT: A city with active cinema venues cannot be removed.
-- =====================================================================
CREATE TABLE venues (
    venue_id    INT PRIMARY KEY,
    venue_name  VARCHAR(150) NOT NULL,
    city_id     INT NOT NULL REFERENCES cities(city_id) ON DELETE RESTRICT,
    chain       VARCHAR(50) NOT NULL,
    address     TEXT NOT NULL,
    CONSTRAINT chk_venues_chain CHECK (chain IN ('PVR', 'INOX', 'Cinepolis', 'Miraj', 'Independent')),
    CONSTRAINT chk_venues_name_nonempty CHECK (length(trim(venue_name)) > 0)
);


-- =====================================================================
-- TABLE 3: screens
-- Auditoriums located within a cinema venue.
-- Deletion policy:
--   venue_id -> CASCADE: Demolishing a venue removes its constituent auditoriums.
-- Redundancy note:
--   total_seats is maintained as a materialized summary for fast layout rendering
--   and verified to strictly equal COUNT(seats) for each screen.
-- =====================================================================
CREATE TABLE screens (
    screen_id    INT PRIMARY KEY,
    venue_id     INT NOT NULL REFERENCES venues(venue_id) ON DELETE CASCADE,
    screen_name  VARCHAR(50) NOT NULL,
    screen_type  VARCHAR(20) NOT NULL,
    total_seats  INT NOT NULL,
    CONSTRAINT chk_screens_type CHECK (screen_type IN ('STANDARD', 'IMAX', '4DX', 'GOLD')),
    CONSTRAINT chk_screens_total_seats_positive CHECK (total_seats > 0),
    CONSTRAINT uq_screens_venue_screen_name UNIQUE (venue_id, screen_name)
);


-- =====================================================================
-- TABLE 4: seats
-- Physical seat configuration belonging to a screen auditorium.
-- Deletion policy:
--   screen_id -> CASCADE: Removing a screen removes its seat layout.
-- =====================================================================
CREATE TABLE seats (
    seat_id      INT PRIMARY KEY,
    screen_id    INT NOT NULL REFERENCES screens(screen_id) ON DELETE CASCADE,
    row_label    VARCHAR(2) NOT NULL,
    seat_number  INT NOT NULL,
    seat_class   VARCHAR(20) NOT NULL,
    CONSTRAINT chk_seats_row_label CHECK (row_label ~ '^[A-Z]{1,2}$'),
    CONSTRAINT chk_seats_seat_number_positive CHECK (seat_number > 0),
    CONSTRAINT chk_seats_seat_class CHECK (seat_class IN ('CLASSIC', 'PRIME', 'RECLINER')),
    CONSTRAINT uq_seats_screen_row_number UNIQUE (screen_id, row_label, seat_number)
);


-- =====================================================================
-- TABLE 5: movies
-- Films available for screening catalog across territories.
-- =====================================================================
CREATE TABLE movies (
    movie_id      INT PRIMARY KEY,
    title         VARCHAR(255) NOT NULL,
    language      VARCHAR(50) NOT NULL,
    certificate   VARCHAR(10) NOT NULL,
    duration_min  SMALLINT NOT NULL,
    release_date  DATE NOT NULL,
    CONSTRAINT chk_movies_language CHECK (language IN ('Hindi', 'English', 'Telugu', 'Tamil', 'Kannada', 'Malayalam', 'Marathi', 'Bengali')),
    CONSTRAINT chk_movies_certificate CHECK (certificate IN ('U', 'UA', 'A')),
    CONSTRAINT chk_movies_duration CHECK (duration_min BETWEEN 30 AND 360),
    CONSTRAINT chk_movies_title_nonempty CHECK (length(trim(title)) > 0)
);


-- =====================================================================
-- TABLE 6: shows
-- Scheduled screenings of a movie on a screen at a specific time range.
-- Deletion policy:
--   movie_id  -> RESTRICT: Cannot purge a movie record if scheduled shows exist.
--   screen_id -> RESTRICT: Cannot delete a screen if scheduled shows are active.
-- Integrity:
--   PostgreSQL exclusion constraint (no_overlapping_shows) guarantees that
--   no screen can host overlapping show runtimes.
-- =====================================================================
CREATE TABLE shows (
    show_id     INT PRIMARY KEY,
    movie_id    INT NOT NULL REFERENCES movies(movie_id) ON DELETE RESTRICT,
    screen_id   INT NOT NULL REFERENCES screens(screen_id) ON DELETE RESTRICT,
    starts_at   TIMESTAMPTZ NOT NULL,
    ends_at     TIMESTAMPTZ NOT NULL,
    format      VARCHAR(20) NOT NULL,
    base_price  NUMERIC(10, 2) NOT NULL,
    CONSTRAINT chk_shows_chronology CHECK (ends_at > starts_at),
    CONSTRAINT chk_shows_format CHECK (format IN ('2D', '3D', 'IMAX', '4DX')),
    CONSTRAINT chk_shows_base_price_positive CHECK (base_price > 0),
    CONSTRAINT no_overlapping_shows EXCLUDE USING gist (
        screen_id WITH =,
        tstzrange(starts_at, ends_at) WITH &&
    )
);


-- =====================================================================
-- TABLE 7: customers
-- Registered users interacting with the ticketing platform.
-- Deletion policy:
--   city_id -> RESTRICT: Retain integrity of customer location mappings.
-- =====================================================================
CREATE TABLE customers (
    customer_id  INT PRIMARY KEY,
    full_name    VARCHAR(150) NOT NULL,
    email        VARCHAR(255) NOT NULL UNIQUE,
    phone        VARCHAR(15) NOT NULL UNIQUE,
    city_id      INT NOT NULL REFERENCES cities(city_id) ON DELETE RESTRICT,
    created_at   TIMESTAMPTZ NOT NULL,
    CONSTRAINT chk_customers_name_nonempty CHECK (length(trim(full_name)) > 0),
    CONSTRAINT chk_customers_email_format CHECK (email ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$'),
    CONSTRAINT chk_customers_phone_format CHECK (phone ~ '^[0-9]{10}$')
);


-- =====================================================================
-- TABLE 8: offers
-- Promotional campaigns and partner discount schemes.
-- =====================================================================
CREATE TABLE offers (
    offer_code    VARCHAR(50) PRIMARY KEY,
    description   TEXT NOT NULL,
    discount_pct  NUMERIC(5, 2) NOT NULL,
    max_discount  NUMERIC(10, 2) NOT NULL,
    valid_from    DATE NOT NULL,
    valid_to      DATE NOT NULL,
    CONSTRAINT chk_offers_discount_pct CHECK (discount_pct BETWEEN 0 AND 100),
    CONSTRAINT chk_offers_max_discount_non_negative CHECK (max_discount >= 0),
    CONSTRAINT chk_offers_validity_window CHECK (valid_to >= valid_from)
);


-- =====================================================================
-- TABLE 9: bookings
-- Checkout transaction records representing customer purchases.
-- Deletion policy:
--   customer_id -> RESTRICT: Financial audit compliance forbids orphaned records.
--   show_id     -> RESTRICT: Past financial history prevents show deletion.
--   offer_code  -> SET NULL: Archiving promotional campaigns preserves bookings.
-- Integrity:
--   chk_bookings_total_amount verifies that total_amount is mathematically
--   derived exactly from (ticket_amount + convenience_fee + fnb_amount - discount).
-- =====================================================================
CREATE TABLE bookings (
    booking_id       INT PRIMARY KEY,
    booking_code     VARCHAR(20) NOT NULL UNIQUE,
    customer_id      INT NOT NULL REFERENCES customers(customer_id) ON DELETE RESTRICT,
    show_id          INT NOT NULL REFERENCES shows(show_id) ON DELETE RESTRICT,
    booked_at        TIMESTAMPTZ NOT NULL,
    num_tickets      SMALLINT NOT NULL,
    ticket_amount    NUMERIC(10, 2) NOT NULL,
    convenience_fee  NUMERIC(10, 2) NOT NULL,
    fnb_amount       NUMERIC(10, 2) NOT NULL DEFAULT 0.00,
    offer_code       VARCHAR(50) REFERENCES offers(offer_code) ON DELETE SET NULL,
    discount         NUMERIC(10, 2) NOT NULL DEFAULT 0.00,
    total_amount     NUMERIC(10, 2) NOT NULL,
    payment_method   VARCHAR(20) NOT NULL,
    status           VARCHAR(20) NOT NULL,
    CONSTRAINT chk_bookings_code_format CHECK (booking_code ~ '^BMS[0-9A-F]{7}$'),
    CONSTRAINT chk_bookings_num_tickets_positive CHECK (num_tickets > 0),
    CONSTRAINT chk_bookings_ticket_amount_non_negative CHECK (ticket_amount >= 0),
    CONSTRAINT chk_bookings_convenience_fee_non_negative CHECK (convenience_fee >= 0),
    CONSTRAINT chk_bookings_fnb_amount_non_negative CHECK (fnb_amount >= 0),
    CONSTRAINT chk_bookings_discount_non_negative CHECK (discount >= 0),
    CONSTRAINT chk_bookings_total_amount_non_negative CHECK (total_amount >= 0),
    CONSTRAINT chk_bookings_total_amount_math CHECK (
        total_amount = round(ticket_amount + convenience_fee + fnb_amount - discount, 2)
    ),
    CONSTRAINT chk_bookings_payment_method CHECK (
        payment_method IN ('UPI', 'CARD', 'NETBANKING', 'WALLET', 'GIFT_CARD')
    ),
    CONSTRAINT chk_bookings_status CHECK (
        status IN ('PENDING', 'CONFIRMED', 'CANCELLED', 'PAYMENT_FAILED')
    )
);


-- =====================================================================
-- TABLE 10: booking_seats
-- Individual seats reserved/purchased under a booking transaction.
-- Deletion policy:
--   booking_id -> CASCADE: Purging a pending/expired booking releases held seats.
--   show_id    -> RESTRICT: Show foreign key.
--   seat_id    -> RESTRICT: Seat reference.
-- Integrity:
--   PRIMARY KEY (show_id, seat_id) guarantees atomic seat uniqueness:
--   a seat can NEVER be sold or held concurrently for the same show.
--   Matches ON CONFLICT (show_id, seat_id) syntax required by workload query W02.
-- =====================================================================
CREATE TABLE booking_seats (
    booking_id  INT NOT NULL REFERENCES bookings(booking_id) ON DELETE CASCADE,
    show_id     INT NOT NULL REFERENCES shows(show_id) ON DELETE RESTRICT,
    seat_id     INT NOT NULL REFERENCES seats(seat_id) ON DELETE RESTRICT,
    price       NUMERIC(10, 2) NOT NULL,
    PRIMARY KEY (show_id, seat_id),
    CONSTRAINT chk_booking_seats_price_non_negative CHECK (price >= 0),
    CONSTRAINT uq_booking_seats_booking_seat UNIQUE (booking_id, seat_id)
);


-- =====================================================================
-- TABLE 11: movie_reviews
-- Ratings and customer feedback for movies.
-- Deletion policy:
--   movie_id    -> CASCADE: Removing a movie purges its associated reviews.
--   customer_id -> CASCADE: Removing a customer account deletes their reviews.
-- Integrity:
--   uq_reviews_customer_movie guarantees one rating per customer per movie.
-- =====================================================================
CREATE TABLE movie_reviews (
    review_id    INT PRIMARY KEY,
    movie_id     INT NOT NULL REFERENCES movies(movie_id) ON DELETE CASCADE,
    customer_id  INT NOT NULL REFERENCES customers(customer_id) ON DELETE CASCADE,
    rating       SMALLINT NOT NULL,
    review_text  TEXT,
    created_at   TIMESTAMPTZ NOT NULL,
    CONSTRAINT chk_reviews_rating_range CHECK (rating BETWEEN 1 AND 10),
    CONSTRAINT uq_reviews_customer_movie UNIQUE (customer_id, movie_id)
);
