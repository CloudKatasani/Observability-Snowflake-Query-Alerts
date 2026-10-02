/* =============================================================================
   07_task_schedule.sql                                   run as OPS_QUERY_MONITOR
   -----------------------------------------------------------------------------
   Serverless task: runs SP_QM_SCAN every minute (worst-case detection delay ≈ 1 min).
   For lower cost use SCHEDULE = '2 MINUTE'.
   ============================================================================= */
USE ROLE OPS_QUERY_MONITOR;
USE SCHEMA OBSERVABILITY.QUERY_ALERTS;

CREATE OR REPLACE TASK OBSERVABILITY.QUERY_ALERTS.TASK_QM_SCAN
  SCHEDULE = '1 MINUTE'
  USER_TASK_MANAGED_INITIAL_WAREHOUSE_SIZE = 'XSMALL'
  SUSPEND_TASK_AFTER_NUM_FAILURES = 10
  COMMENT = 'Real-time alerts: long-running (>=15 min), queued (>=5 min), lock-blocked (>=5 min) queries'
AS
  CALL OBSERVABILITY.QUERY_ALERTS.SP_QM_SCAN();

ALTER TASK OBSERVABILITY.QUERY_ALERTS.TASK_QM_SCAN RESUME;
