/* =============================================================================
   00_setup_role_database.sql                                   run as ACCOUNTADMIN
   -----------------------------------------------------------------------------
   Role, database/schema and privileges for Snowflake real-time query alerts.
   All objects live in OBSERVABILITY.QUERY_ALERTS. An existing OBSERVABILITY
   database is reused (CREATE ... IF NOT EXISTS).
   ============================================================================= */
USE ROLE ACCOUNTADMIN;

CREATE ROLE IF NOT EXISTS OPS_QUERY_MONITOR COMMENT = 'Runs real-time query alerting (OBSERVABILITY.QUERY_ALERTS)';
GRANT ROLE OPS_QUERY_MONITOR TO ROLE SYSADMIN;

CREATE DATABASE IF NOT EXISTS OBSERVABILITY;
CREATE SCHEMA   IF NOT EXISTS OBSERVABILITY.QUERY_ALERTS
  COMMENT = 'Real-time alerts for long-running, queued and lock-blocked queries';
GRANT USAGE ON DATABASE OBSERVABILITY TO ROLE OPS_QUERY_MONITOR;
GRANT OWNERSHIP ON SCHEMA OBSERVABILITY.QUERY_ALERTS TO ROLE OPS_QUERY_MONITOR COPY CURRENT GRANTS;

-- Serverless task execution
GRANT EXECUTE TASK, EXECUTE MANAGED TASK ON ACCOUNT TO ROLE OPS_QUERY_MONITOR;

/* -----------------------------------------------------------------------------
   MONITOR on every warehouse: required to see OTHER users' queries in
   INFORMATION_SCHEMA.QUERY_HISTORY_BY_WAREHOUSE().
   Re-run this block whenever a warehouse is created (add it to the
   warehouse-creation runbook).
   ----------------------------------------------------------------------------- */
EXECUTE IMMEDIATE $$
DECLARE
  v_wh  VARCHAR;
  v_sql VARCHAR;
  v_n   NUMBER DEFAULT 0;
BEGIN
  SHOW WAREHOUSES;
  LET rs RESULTSET := (SELECT "name" AS WH FROM TABLE(RESULT_SCAN(LAST_QUERY_ID())));
  LET c CURSOR FOR rs;
  FOR r IN c DO
    v_wh := r.WH;
    v_sql := 'GRANT MONITOR ON WAREHOUSE "' || v_wh || '" TO ROLE OPS_QUERY_MONITOR';
    EXECUTE IMMEDIATE :v_sql;
    v_n := v_n + 1;
  END FOR;
  RETURN 'MONITOR granted on ' || v_n || ' warehouses';
END;
$$;

-- Optional: a warehouse for admins to query the views interactively (the task itself is serverless)
-- GRANT USAGE ON WAREHOUSE <ADMIN_WH> TO ROLE OPS_QUERY_MONITOR;
-- GRANT ROLE OPS_QUERY_MONITOR TO USER <admin_user>;
