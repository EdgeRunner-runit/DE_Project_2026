-- =====================================================================
-- BookMyShow DBMS Project - Database Security & Role-Based Access Control
-- Schema: bms
-- Authors: Team T0132
-- Description:
--   Enterprise Role-Based Access Control (RBAC) architecture enforcing
--   Principle of Least Privilege (PoLP) and PostgreSQL Row-Level Security (RLS).
-- =====================================================================

SET search_path TO bms;

-- ---------------------------------------------------------------------
-- 1. Create Granular Database Roles
-- ---------------------------------------------------------------------
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'bms_app_user') THEN
        CREATE ROLE bms_app_user WITH LOGIN PASSWORD 'app_secure_pwd';
    END IF;

    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'bms_cinema_manager') THEN
        CREATE ROLE bms_cinema_manager WITH LOGIN PASSWORD 'manager_secure_pwd';
    END IF;

    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'bms_data_analyst') THEN
        CREATE ROLE bms_data_analyst WITH LOGIN PASSWORD 'analyst_secure_pwd';
    END IF;

    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'bms_dba_admin') THEN
        CREATE ROLE bms_dba_admin WITH LOGIN SUPERUSER PASSWORD 'dba_secure_pwd';
    END IF;
END $$;

-- ---------------------------------------------------------------------
-- 2. Schema Usage Permissions
-- ---------------------------------------------------------------------
GRANT USAGE ON SCHEMA bms TO bms_app_user, bms_cinema_manager, bms_data_analyst;

-- ---------------------------------------------------------------------
-- 3. Application User Permissions (bms_app_user)
-- Can browse catalogs, search movies, create bookings, and write reviews.
-- No delete permissions on catalog tables (movies, shows, venues, cities).
-- ---------------------------------------------------------------------
GRANT SELECT ON cities, venues, screens, seats, movies, shows, offers TO bms_app_user;
GRANT SELECT, INSERT, UPDATE (status) ON bookings TO bms_app_user;
GRANT SELECT, INSERT, DELETE ON booking_seats TO bms_app_user;
GRANT SELECT, INSERT, UPDATE ON movie_reviews TO bms_app_user;
GRANT SELECT, INSERT, UPDATE ON customers TO bms_app_user;
GRANT EXECUTE ON FUNCTION func_create_pending_booking, func_lock_seats_atomic TO bms_app_user;

-- ---------------------------------------------------------------------
-- 4. Data Analyst Permissions (bms_data_analyst)
-- Read-only access to historical data and analytical views. Zero write access.
-- ---------------------------------------------------------------------
GRANT SELECT ON ALL TABLES IN SCHEMA bms TO bms_data_analyst;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON ALL TABLES IN SCHEMA bms FROM bms_data_analyst;

-- ---------------------------------------------------------------------
-- 5. Row-Level Security (RLS) for Cinema Managers
-- Cinema managers should only see data for venues within their assigned cinema chain.
-- ---------------------------------------------------------------------
ALTER TABLE venues ENABLE ROW LEVEL SECURITY;
ALTER TABLE shows ENABLE ROW LEVEL SECURITY;

-- Policy: Cinema managers can only view venues belonging to their session chain
CREATE POLICY manager_venue_isolation_policy ON venues
    FOR SELECT
    TO bms_cinema_manager
    USING (chain = current_setting('bms.current_manager_chain', true));

-- Policy: Managers only see shows hosted on screens of their assigned venues
CREATE POLICY manager_show_isolation_policy ON shows
    FOR SELECT
    TO bms_cinema_manager
    USING (
        screen_id IN (
            SELECT screen_id FROM screens sc
            JOIN venues v ON v.venue_id = sc.venue_id
            WHERE v.chain = current_setting('bms.current_manager_chain', true)
        )
    );

\echo '==> Enterprise Security, RBAC Privileges, and Row-Level Security (RLS) Configured!'
