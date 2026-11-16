-- =====================================================================
-- BookMyShow DBMS Test Suite: Automated Relational Integrity Harness
-- Schema: bms
-- Authors: Team T0132
-- Description:
--   Executes automated assertions against the bms database schema and
--   data. Validates relational integrity, foreign key references, domain
--   constraints, and financial arithmetic consistency.
--
-- EXECUTION:
--   psql -d <database_name> -f tests/test_integrity.sql
-- =====================================================================

SET search_path TO bms;

\echo '====================================================================='
\echo 'RUNNING AUTOMATED RELATIONAL INTEGRITY TEST SUITE'
\echo '====================================================================='

CREATE TEMP TABLE test_results (
    test_id      INT PRIMARY KEY,
    test_name    TEXT NOT NULL,
    status       TEXT NOT NULL CHECK (status IN ('PASS', 'FAIL')),
    details      TEXT NOT NULL
);

-- Test 1: Verify all 11 tables exist in bms schema
INSERT INTO test_results (test_id, test_name, status, details)
SELECT 1, 'Table Existence Test (11 tables)',
       CASE WHEN count(*) = 11 THEN 'PASS' ELSE 'FAIL' END,
       format('Found %s of 11 expected tables in bms schema', count(*))
FROM information_schema.tables 
WHERE table_schema = 'bms' AND table_type = 'BASE TABLE';

-- Test 2: Foreign Key Integrity (No orphaned booking_seats)
INSERT INTO test_results (test_id, test_name, status, details)
SELECT 2, 'Orphaned Booking Seats Test',
       CASE WHEN count(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
       format('Found %s orphaned booking_seats records', count(*))
FROM booking_seats bs
LEFT JOIN bookings b ON b.booking_id = bs.booking_id
WHERE b.booking_id IS NULL;

-- Test 3: Seat Layout to Screen Referential Consistency
INSERT INTO test_results (test_id, test_name, status, details)
SELECT 3, 'Seat-Screen Association Test',
       CASE WHEN count(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
       format('Found %s booked seats on mismatched screens', count(*))
FROM booking_seats bs
JOIN shows s  ON s.show_id = bs.show_id
JOIN seats se ON se.seat_id = bs.seat_id
WHERE s.screen_id <> se.screen_id;

-- Test 4: Financial Balance Equation (total_amount = ticket + fee + fnb - discount)
INSERT INTO test_results (test_id, test_name, status, details)
SELECT 4, 'Financial Balance Equation Test',
       CASE WHEN count(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
       format('Found %s bookings with arithmetic total_amount mismatch', count(*))
FROM bookings
WHERE total_amount <> round(ticket_amount + convenience_fee + fnb_amount - discount, 2);

-- Test 5: Seat Hold Invariant for Inactive Bookings
INSERT INTO test_results (test_id, test_name, status, details)
SELECT 5, 'Cancelled Booking Seat Lock Isolation Test',
       CASE WHEN count(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
       format('Found %s seats held by cancelled/failed bookings', count(*))
FROM booking_seats bs
JOIN bookings b ON b.booking_id = bs.booking_id
WHERE b.status IN ('CANCELLED', 'PAYMENT_FAILED');

-- Test 6: Active Ticket Count Invariant
INSERT INTO test_results (test_id, test_name, status, details)
SELECT 6, 'Active Booking Ticket Count Invariant',
       CASE WHEN count(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
       format('Found %s active bookings with ticket_amount != seat count', count(*))
FROM bookings b
JOIN (
    SELECT booking_id, count(*) AS held_seats
    FROM booking_seats
    GROUP BY booking_id
) bs ON bs.booking_id = b.booking_id
WHERE b.status IN ('CONFIRMED', 'PENDING')
  AND b.num_tickets <> bs.held_seats;

-- Test 7: Show Non-Overlap Invariant
INSERT INTO test_results (test_id, test_name, status, details)
SELECT 7, 'Show Screen Non-Overlap Invariant',
       CASE WHEN count(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
       format('Found %s overlapping showtime pairs', count(*))
FROM shows s1
JOIN shows s2 ON s1.screen_id = s2.screen_id 
             AND s1.show_id < s2.show_id
             AND tstzrange(s1.starts_at, s1.ends_at) && tstzrange(s2.starts_at, s2.ends_at);

-- Test 8: Auditorium Capacity Consistency
INSERT INTO test_results (test_id, test_name, status, details)
SELECT 8, 'Screen Total Seats Capacity Verification',
       CASE WHEN count(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
       format('Found %s screens where total_seats != count(seats)', count(*))
FROM screens sc
JOIN (
    SELECT screen_id, count(*) AS actual_seats
    FROM seats
    GROUP BY screen_id
) se ON se.screen_id = sc.screen_id
WHERE sc.total_seats <> se.actual_seats;

-- Test 9: Unique Booking Code Format Conformance
INSERT INTO test_results (test_id, test_name, status, details)
SELECT 9, 'Booking Code Regex Format Test',
       CASE WHEN count(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
       format('Found %s booking codes violating BMS[0-9A-F]{7} pattern', count(*))
FROM bookings
WHERE booking_code !~ '^BMS[0-9A-F]{7}$';

-- Test 10: Phone & Email Syntax Validation
INSERT INTO test_results (test_id, test_name, status, details)
SELECT 10, 'Customer Contact Information Format Test',
       CASE WHEN count(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
       format('Found %s customers with invalid phone/email format', count(*))
FROM customers
WHERE phone !~ '^[0-9]{10}$' 
   OR email !~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$';

-- Output Test Report Table
\echo '---------------------------------------------------------------------'
\echo 'TEST SUMMARY REPORT'
\echo '---------------------------------------------------------------------'
SELECT test_id, test_name, status, details FROM test_results ORDER BY test_id;

-- Fail fast if any test failed
DO $$
DECLARE
    failures INT;
BEGIN
    SELECT count(*) INTO failures FROM test_results WHERE status = 'FAIL';
    IF failures > 0 THEN
        RAISE EXCEPTION 'TEST SUITE FAILED: % checks failed validation!', failures;
    ELSE
        RAISE NOTICE 'TEST SUITE PASSED: All 10 relational integrity tests succeeded!';
    END IF;
END $$;
