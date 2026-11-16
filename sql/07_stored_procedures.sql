-- =====================================================================
-- BookMyShow DBMS Project - Stored Procedures & Business Logic Engine
-- Schema: bms
-- Authors: Team T0132
-- Description:
--   Enterprise stored procedures encapsulating transaction lifecycles:
--     1. proc_create_pending_booking: Initiates booking and creates PENDING hold.
--     2. proc_lock_seats_for_booking: Atomic seat locking with conflict detection.
--     3. proc_confirm_payment: Confirms order upon payment gateway callback.
--     4. proc_expire_stale_holds: Releases expired seat holds (> 10 mins).
--     5. proc_apply_weekend_surge: Dynamic surge pricing adjustment.
-- =====================================================================

SET search_path TO bms;

-- ---------------------------------------------------------------------
-- 1. Create Pending Booking Transaction (Wraps Workload Query W01)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION bms.func_create_pending_booking(
    p_booking_id      INT,
    p_booking_code    VARCHAR,
    p_customer_id     INT,
    p_show_id         INT,
    p_num_tickets     SMALLINT,
    p_ticket_amount   NUMERIC,
    p_convenience_fee NUMERIC,
    p_fnb_amount      NUMERIC,
    p_discount        NUMERIC,
    p_payment_method  VARCHAR
) RETURNS INT AS $$
DECLARE
    v_total_amount NUMERIC := round(p_ticket_amount + p_convenience_fee + p_fnb_amount - p_discount, 2);
BEGIN
    INSERT INTO bookings (
        booking_id, booking_code, customer_id, show_id, booked_at,
        num_tickets, ticket_amount, convenience_fee, fnb_amount, discount,
        total_amount, payment_method, status
    ) VALUES (
        p_booking_id, p_booking_code, p_customer_id, p_show_id, now(),
        p_num_tickets, p_ticket_amount, p_convenience_fee, p_fnb_amount, p_discount,
        v_total_amount, p_payment_method, 'PENDING'
    );

    RETURN p_booking_id;
END;
$$ LANGUAGE plpgsql;


-- ---------------------------------------------------------------------
-- 2. Atomic Seat Locking Function (Wraps Workload Query W02)
-- Uses SELECT ... FOR UPDATE to eliminate concurrency race conditions.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION bms.func_lock_seats_atomic(
    p_booking_id INT,
    p_seat_ids   INT[],
    p_seat_price NUMERIC
) RETURNS INT AS $$
DECLARE
    v_show_id INT;
    v_seat_id INT;
    v_locked_count INT := 0;
BEGIN
    -- Verify booking exists and is in PENDING state
    SELECT show_id INTO v_show_id
    FROM bookings
    WHERE booking_id = p_booking_id AND status = 'PENDING'
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Booking % not found or not in PENDING state', p_booking_id;
    END IF;

    -- Iterate and insert seat locks
    FOREACH v_seat_id IN ARRAY p_seat_ids LOOP
        BEGIN
            INSERT INTO booking_seats (booking_id, show_id, seat_id, price)
            VALUES (p_booking_id, v_show_id, v_seat_id, p_seat_price);
            v_locked_count := v_locked_count + 1;
        EXCEPTION WHEN unique_violation THEN
            -- Handle conflict: seat already locked by another user
            RAISE NOTICE 'Seat % for show % is already locked', v_seat_id, v_show_id;
        END;
    END LOOP;

    RETURN v_locked_count;
END;
$$ LANGUAGE plpgsql;


-- ---------------------------------------------------------------------
-- 3. Confirm Payment Callback (Wraps Workload Query W03)
-- Transitions booking state from PENDING to CONFIRMED.
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE bms.proc_confirm_payment(p_booking_id INT)
LANGUAGE plpgsql AS $$
BEGIN
    UPDATE bookings
    SET status = 'CONFIRMED'
    WHERE booking_id = p_booking_id AND status = 'PENDING';

    IF NOT FOUND THEN
        RAISE WARNING 'Booking % was not in PENDING state or does not exist', p_booking_id;
    ELSE
        RAISE NOTICE 'Booking % successfully confirmed', p_booking_id;
    END IF;
END;
$$;


-- ---------------------------------------------------------------------
-- 4. Expire Stale Seat Holds (Wraps Workload Query W04)
-- Releases physical seats held by pending checkouts older than 10 minutes.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION bms.func_expire_stale_holds(p_reference_time TIMESTAMPTZ DEFAULT now())
RETURNS INT AS $$
DECLARE
    v_expired_count INT;
BEGIN
    -- Delete held seats cascading from expired pending bookings
    WITH expired_bookings AS (
        SELECT booking_id
        FROM bookings
        WHERE status = 'PENDING'
          AND booked_at < p_reference_time - interval '10 minutes'
        FOR UPDATE SKIP LOCKED
    ),
    deleted_seats AS (
        DELETE FROM booking_seats bs
        USING expired_bookings eb
        WHERE bs.booking_id = eb.booking_id
        RETURNING bs.booking_id
    )
    SELECT count(*) INTO v_expired_count FROM deleted_seats;

    -- Update booking status to CANCELLED
    UPDATE bookings b
    SET status = 'CANCELLED'
    WHERE status = 'PENDING'
      AND booked_at < p_reference_time - interval '10 minutes';

    RETURN v_expired_count;
END;
$$ LANGUAGE plpgsql;


-- ---------------------------------------------------------------------
-- 5. Dynamic Weekend Surge Pricing (Wraps Workload Query W05)
-- Increases weekend show pricing by multiplier (e.g. 1.10 for +10%).
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION bms.func_apply_weekend_surge(
    p_movie_id INT,
    p_start_date DATE,
    p_surge_multiplier NUMERIC DEFAULT 1.10
) RETURNS INT AS $$
DECLARE
    v_updated_count INT;
BEGIN
    UPDATE shows
    SET base_price = round(base_price * p_surge_multiplier, 0)
    WHERE movie_id = p_movie_id
      AND starts_at >= p_start_date::timestamptz
      AND EXTRACT(ISODOW FROM starts_at) IN (6, 7);

    GET DIAGNOSTICS v_updated_count = ROW_COUNT;
    RETURN v_updated_count;
END;
$$ LANGUAGE plpgsql;
