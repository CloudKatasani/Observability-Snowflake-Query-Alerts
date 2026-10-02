/* =============================================================================
   08_views.sql                                           run as OPS_QUERY_MONITOR
   -----------------------------------------------------------------------------
   V_QM_OPEN_ALERTS     what is breaching right now (with ready-made cancel SQL)
   V_QM_ALERT_HISTORY   daily counts by type / warehouse (trend and tuning)
   V_QM_MONITOR_HEALTH  last runs of the task (is the monitor itself healthy?)
   ============================================================================= */
USE ROLE OPS_QUERY_MONITOR;
USE SCHEMA OBSERVABILITY.QUERY_ALERTS;

CREATE OR REPLACE VIEW OBSERVABILITY.QUERY_ALERTS.V_QM_OPEN_ALERTS
  COMMENT = 'Queries currently breaching a threshold (refreshed every minute by TASK_QM_SCAN)'
AS
SELECT ALERT_TYPE, QUERY_ID, WAREHOUSE_NAME, WAREHOUSE_SIZE, USER_NAME, ROLE_NAME, DATABASE_NAME, QUERY_TYPE,
       QUERY_START_TIME, MAX_MINUTES AS MINUTES, FIRST_DETECTED_AT, LAST_NOTIFIED_AT, NOTIFY_COUNT,
       PAGERDUTY_TRIGGERED_AT, LOCKED_RESOURCE, BLOCKER_QUERY_ID, BLOCKER_TXN_ID, LAST_CHANNEL_STATUS,
       'SELECT SYSTEM$CANCEL_QUERY(''' || QUERY_ID || ''');'                                   AS CANCEL_SQL,
       IFF(BLOCKER_TXN_ID IS NOT NULL, 'SELECT SYSTEM$ABORT_TRANSACTION(' || BLOCKER_TXN_ID || ');', NULL) AS RELEASE_LOCK_SQL
  FROM OBSERVABILITY.QUERY_ALERTS.QM_ALERT_LOG
 WHERE RESOLVED_AT IS NULL
 ORDER BY MINUTES DESC;

CREATE OR REPLACE VIEW OBSERVABILITY.QUERY_ALERTS.V_QM_ALERT_HISTORY
  COMMENT = 'Daily alert counts by type and warehouse'
AS
SELECT FIRST_DETECTED_AT::DATE             AS ALERT_DATE,
       ALERT_TYPE,
       WAREHOUSE_NAME,
       COUNT(*)                            AS ALERTS,
       COUNT_IF(PAGERDUTY_TRIGGERED_AT IS NOT NULL) AS PAGED,
       ROUND(AVG(MAX_MINUTES), 1)          AS AVG_MINUTES,
       MAX(MAX_MINUTES)                    AS MAX_MINUTES,
       COUNT(DISTINCT USER_NAME)           AS USERS
  FROM OBSERVABILITY.QUERY_ALERTS.QM_ALERT_LOG
 GROUP BY 1, 2, 3;

CREATE OR REPLACE VIEW OBSERVABILITY.QUERY_ALERTS.V_QM_MONITOR_HEALTH
  COMMENT = 'Last 7 days of TASK_QM_SCAN runs (state, return value, errors)'
AS
SELECT NAME, STATE, SCHEDULED_TIME, COMPLETED_TIME,
       DATEDIFF('second', QUERY_START_TIME, COMPLETED_TIME) AS RUN_SECONDS,
       RETURN_VALUE, ERROR_MESSAGE
  FROM TABLE(OBSERVABILITY.INFORMATION_SCHEMA.TASK_HISTORY(
         TASK_NAME => 'TASK_QM_SCAN',
         SCHEDULED_TIME_RANGE_START => DATEADD('day', -7, CURRENT_TIMESTAMP()),
         RESULT_LIMIT => 10000));
