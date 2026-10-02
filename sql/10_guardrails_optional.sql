/* =============================================================================
   10_guardrails_optional.sql                     OPTIONAL — prevention, not alerting
   -----------------------------------------------------------------------------
   Alerts tell people; these parameters make Snowflake act. Apply per policy,
   per warehouse or account. Values below are examples.
   ============================================================================= */

-- Hard stop for statements that run too long (default is 2 days)
-- ALTER WAREHOUSE <wh> SET STATEMENT_TIMEOUT_IN_SECONDS = 7200;            -- 2 h

-- Cancel statements that sit in a warehouse queue too long (default: never)
-- ALTER WAREHOUSE <wh> SET STATEMENT_QUEUED_TIMEOUT_IN_SECONDS = 1800;     -- 30 min

-- Stop lock waits from hanging for the 12 h default
-- ALTER ACCOUNT SET LOCK_TIMEOUT = 1800;                                    -- seconds

-- Reduce queueing on busy warehouses
-- ALTER WAREHOUSE <wh> SET MIN_CLUSTER_COUNT = 1 MAX_CLUSTER_COUNT = 3 SCALING_POLICY = 'STANDARD';  -- multi-cluster (Enterprise+)
-- ALTER WAREHOUSE <wh> SET WAREHOUSE_SIZE = 'LARGE';
