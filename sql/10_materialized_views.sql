-- =====================================================================
-- BookMyShow DBMS Project - Materialized Views & Concurrent Refresh Layer
-- Schema: bms
-- Authors: Team T0132
-- Description:
--   High-performance analytical materialized views for compute-heavy
--   reporting queries (R12, R15, R18). Includes unique indexation enabling
--   REFRESH MATERIALIZED VIEW CONCURRENTLY (zero reader downtime).
-- =====================================================================

SET search_path TO bms;

-- ---------------------------------------------------------------------
-- 1. Materialized View: mv_cinema_monthly_revenue (Powers Query R12)
-- Pre-aggregates revenue, bookings, and ticket counts per cinema per month.
-- Eliminates multi-table joins across 3M bookings and 160k shows.
-- ---------------------------------------------------------------------
CREATE MATERIALIZED VIEW bms.mv_cinema_monthly_revenue AS
SELECT 
    v.venue_id,
    v.venue_name,
    c.city_name,
    v.chain,
    date_trunc('month', s.starts_at)::date AS revenue_month,
    count(DISTINCT b.booking_id) AS total_bookings,
    sum(b.total_amount) AS total_revenue,
    sum(b.num_tickets) AS total_tickets_sold
FROM venues v
JOIN cities c   ON c.city_id = v.city_id
JOIN screens sc ON sc.venue_id = v.venue_id
JOIN shows s    ON s.screen_id = sc.screen_id
JOIN bookings b ON b.show_id = s.show_id
WHERE b.status = 'CONFIRMED'
GROUP BY v.venue_id, v.venue_name, c.city_name, v.chain, date_trunc('month', s.starts_at)::date
WITH NO DATA;

-- UNIQUE INDEX enables REFRESH CONCURRENTLY
CREATE UNIQUE INDEX idx_mv_cinema_rev_pk 
ON bms.mv_cinema_monthly_revenue (venue_id, revenue_month);


-- ---------------------------------------------------------------------
-- 2. Materialized View: mv_booking_traffic_heatmap (Powers Query R15)
-- Pre-computes 7x24 heatmap of booking volume by weekday and hour.
-- Turns full table scan of 3M rows into instant 168-row index seek (< 1 ms).
-- ---------------------------------------------------------------------
CREATE MATERIALIZED VIEW bms.mv_booking_traffic_heatmap AS
SELECT 
    EXTRACT(ISODOW FROM booked_at)::smallint AS day_of_week,
    EXTRACT(HOUR   FROM booked_at)::smallint AS booking_hour,
    count(*) AS total_bookings,
    sum(total_amount) AS total_volume
FROM bookings
GROUP BY EXTRACT(ISODOW FROM booked_at), EXTRACT(HOUR FROM booked_at)
WITH NO DATA;

CREATE UNIQUE INDEX idx_mv_heatmap_pk 
ON bms.mv_booking_traffic_heatmap (day_of_week, booking_hour);


-- ---------------------------------------------------------------------
-- 3. Materialized View: mv_chain_cancellation_rates (Powers Query R18)
-- Tracks operational reliability and cancellation ratios per cinema brand.
-- ---------------------------------------------------------------------
CREATE MATERIALIZED VIEW bms.mv_chain_cancellation_rates AS
SELECT 
    v.chain,
    count(*) AS total_bookings,
    count(*) FILTER (WHERE b.status = 'CANCELLED') AS cancelled_bookings,
    round(
        count(*) FILTER (WHERE b.status = 'CANCELLED')::numeric / count(*) * 100, 2
    ) AS cancellation_rate_pct
FROM venues v
JOIN screens sc ON sc.venue_id = v.venue_id
JOIN shows s    ON s.screen_id = sc.screen_id
JOIN bookings b ON b.show_id = s.show_id
GROUP BY v.chain
WITH NO DATA;

CREATE UNIQUE INDEX idx_mv_chain_cancel_pk 
ON bms.mv_chain_cancellation_rates (chain);


-- ---------------------------------------------------------------------
-- 4. Stored Procedure: Concurrent Non-Blocking View Refresh
-- Can be triggered via cron or scheduler during off-peak windows.
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE bms.proc_refresh_analytical_views()
LANGUAGE plpgsql AS $$
BEGIN
    RAISE NOTICE 'Refreshing mv_cinema_monthly_revenue concurrently...';
    REFRESH MATERIALIZED VIEW CONCURRENTLY bms.mv_cinema_monthly_revenue;

    RAISE NOTICE 'Refreshing mv_booking_traffic_heatmap concurrently...';
    REFRESH MATERIALIZED VIEW CONCURRENTLY bms.mv_booking_traffic_heatmap;

    RAISE NOTICE 'Refreshing mv_chain_cancellation_rates concurrently...';
    REFRESH MATERIALIZED VIEW CONCURRENTLY bms.mv_chain_cancellation_rates;

    RAISE NOTICE 'All analytical materialized views refreshed without reader locks.';
END;
$$;
