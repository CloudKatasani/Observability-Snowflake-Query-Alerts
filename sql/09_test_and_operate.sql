/* =============================================================================
   09_test_and_operate.sql                                run as OPS_QUERY_MONITOR
   -----------------------------------------------------------------------------
   A. SP_QM_TEST_CHANNELS — sends a clearly marked TEST message through every
      ENABLED channel (PagerDuty: trigger, then resolve) using a fake query row.
   B. End-to-end test with real long-running and lock-blocked queries.
   C. Day-2 operations: tune, exclude, pause, health.
   ============================================================================= */
USE ROLE OPS_QUERY_MONITOR;
USE SCHEMA OBSERVABILITY.QUERY_ALERTS;

/* ---------- A. channel test ------------------------------------------------- */
CREATE OR REPLACE PROCEDURE OBSERVABILITY.QUERY_ALERTS.SP_QM_TEST_CHANNELS()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
  v_email_on BOOLEAN; v_teams_on BOOLEAN; v_slack_on BOOLEAN; v_pd_on BOOLEAN;
  v_ret      VARCHAR;
  v_out      VARCHAR DEFAULT '';
  v_subject  VARCHAR;
BEGIN
  SELECT COALESCE(TRY_TO_BOOLEAN(MAX(IFF(PARAM_NAME = 'EMAIL_ENABLED',     PARAM_VALUE, NULL))), FALSE),
         COALESCE(TRY_TO_BOOLEAN(MAX(IFF(PARAM_NAME = 'TEAMS_ENABLED',     PARAM_VALUE, NULL))), FALSE),
         COALESCE(TRY_TO_BOOLEAN(MAX(IFF(PARAM_NAME = 'SLACK_ENABLED',     PARAM_VALUE, NULL))), FALSE),
         COALESCE(TRY_TO_BOOLEAN(MAX(IFF(PARAM_NAME = 'PAGERDUTY_ENABLED', PARAM_VALUE, NULL))), FALSE)
    INTO :v_email_on, :v_teams_on, :v_slack_on, :v_pd_on
    FROM OBSERVABILITY.QUERY_ALERTS.QM_CONFIG;

  -- same shape as the table built by SP_QM_SCAN
  CREATE OR REPLACE TEMPORARY TABLE OBSERVABILITY.QUERY_ALERTS.QM_CANDIDATES (
    QUERY_ID VARCHAR, ALERT_TYPE VARCHAR, EXECUTION_STATUS VARCHAR, MINUTES NUMBER(10,1),
    WAREHOUSE_NAME VARCHAR, WAREHOUSE_SIZE VARCHAR, USER_NAME VARCHAR, ROLE_NAME VARCHAR,
    DATABASE_NAME VARCHAR, QUERY_TYPE VARCHAR, QUERY_TAG VARCHAR, QUERY_START_TIME TIMESTAMP_LTZ,
    QUERY_TEXT_SNIPPET VARCHAR, LOCKED_RESOURCE VARCHAR, BLOCKER_QUERY_ID VARCHAR, BLOCKER_TXN_ID VARCHAR,
    TO_NOTIFY BOOLEAN DEFAULT FALSE, PD_ELIGIBLE BOOLEAN DEFAULT FALSE, PD_NOTIFY BOOLEAN DEFAULT FALSE);
  INSERT INTO OBSERVABILITY.QUERY_ALERTS.QM_CANDIDATES
    (QUERY_ID, ALERT_TYPE, EXECUTION_STATUS, MINUTES, WAREHOUSE_NAME, WAREHOUSE_SIZE, USER_NAME, ROLE_NAME,
     QUERY_START_TIME, LOCKED_RESOURCE, BLOCKER_QUERY_ID, BLOCKER_TXN_ID, TO_NOTIFY, PD_ELIGIBLE, PD_NOTIFY)
  VALUES
    ('TEST-0000-LONG',  'LONG_RUNNING', 'RUNNING', 42.0, 'TEST_WH', 'Medium', 'TEST_USER', 'TEST_ROLE',
     CURRENT_TIMESTAMP(), NULL, NULL, NULL, TRUE, TRUE, TRUE),
    ('TEST-0000-BLOCK', 'BLOCKED', 'BLOCKED', 7.5, 'TEST_WH', 'Medium', 'TEST_USER', 'TEST_ROLE',
     CURRENT_TIMESTAMP(), 'TEST_DB.PUBLIC.ORDERS', 'TEST-0000-HOLDER', '1234567890', TRUE, FALSE, FALSE);

  v_subject := '[TEST][Snowflake ' || CURRENT_ACCOUNT() || '] query alert channel test — please ignore';

  IF (v_email_on) THEN
    BEGIN CALL OBSERVABILITY.QUERY_ALERTS.SP_QM_SEND_EMAIL(:v_subject) INTO :v_ret; v_out := v_out || v_ret || ' ';
    EXCEPTION WHEN OTHER THEN v_out := v_out || 'EMAIL:FAILED(' || LEFT(SQLERRM, 120) || ') '; END;
  END IF;
  IF (v_teams_on) THEN
    BEGIN CALL OBSERVABILITY.QUERY_ALERTS.SP_QM_SEND_TEAMS(:v_subject) INTO :v_ret; v_out := v_out || v_ret || ' ';
    EXCEPTION WHEN OTHER THEN v_out := v_out || 'TEAMS:FAILED(' || LEFT(SQLERRM, 120) || ') '; END;
  END IF;
  IF (v_slack_on) THEN
    BEGIN CALL OBSERVABILITY.QUERY_ALERTS.SP_QM_SEND_SLACK(:v_subject) INTO :v_ret; v_out := v_out || v_ret || ' ';
    EXCEPTION WHEN OTHER THEN v_out := v_out || 'SLACK:FAILED(' || LEFT(SQLERRM, 120) || ') '; END;
  END IF;
  IF (v_pd_on) THEN
    BEGIN
      CALL OBSERVABILITY.QUERY_ALERTS.SP_QM_SEND_PAGERDUTY('TRIGGER', :v_subject) INTO :v_ret; v_out := v_out || v_ret || ' ';
      CALL SYSTEM$WAIT(20, 'SECONDS');
      CALL OBSERVABILITY.QUERY_ALERTS.SP_QM_SEND_PAGERDUTY('RESOLVE', '[TEST] resolved') INTO :v_ret; v_out := v_out || v_ret || ' ';
    EXCEPTION WHEN OTHER THEN v_out := v_out || 'PAGERDUTY:FAILED(' || LEFT(SQLERRM, 120) || ') '; END;
  END IF;

  RETURN IFF(v_out = '', 'No channel is enabled in QM_CONFIG', v_out);
END;
$$;

-- CALL OBSERVABILITY.QUERY_ALERTS.SP_QM_TEST_CHANNELS();

/* ---------- B. end-to-end test --------------------------------------------- */
-- 1. Lower thresholds:
--    UPDATE OBSERVABILITY.QUERY_ALERTS.QM_CONFIG SET PARAM_VALUE = '1'
--     WHERE PARAM_NAME IN ('LONG_RUNNING_MIN', 'QUEUED_MIN', 'BLOCKED_MIN', 'PAGERDUTY_MIN_MINUTES');
-- 2. Long-running : on any warehouse   SELECT SYSTEM$WAIT(3, 'MINUTES');
-- 3. Lock-blocked : session A  BEGIN; UPDATE <test_table> SET c = c;        -- do not commit
--                   session B  UPDATE <test_table> SET c = c;                -- waits on A's lock
-- 4. Wait for the next task run, or run once:  CALL OBSERVABILITY.QUERY_ALERTS.SP_QM_SCAN();
-- 5. Session A: ROLLBACK;  → next run resolves the alert (and PagerDuty incident).
-- 6. Restore: 15 / 5 / 5 / 30.

/* ---------- C. operate ------------------------------------------------------ */
-- Open alerts / history / monitor health
-- SELECT * FROM OBSERVABILITY.QUERY_ALERTS.V_QM_OPEN_ALERTS;
-- SELECT * FROM OBSERVABILITY.QUERY_ALERTS.V_QM_ALERT_HISTORY ORDER BY ALERT_DATE DESC;
-- SELECT * FROM OBSERVABILITY.QUERY_ALERTS.V_QM_MONITOR_HEALTH ORDER BY SCHEDULED_TIME DESC LIMIT 20;

-- Tune / exclude / switch channels (takes effect on the next run)
-- UPDATE OBSERVABILITY.QUERY_ALERTS.QM_CONFIG SET PARAM_VALUE = '20'              WHERE PARAM_NAME = 'LONG_RUNNING_MIN';
-- UPDATE OBSERVABILITY.QUERY_ALERTS.QM_CONFIG SET PARAM_VALUE = 'ETL_WH,DS_WH'    WHERE PARAM_NAME = 'EXCLUDED_WAREHOUSES';
-- UPDATE OBSERVABILITY.QUERY_ALERTS.QM_CONFIG SET PARAM_VALUE = 'SVC_DBT'         WHERE PARAM_NAME = 'EXCLUDED_USERS';
-- UPDATE OBSERVABILITY.QUERY_ALERTS.QM_CONFIG SET PARAM_VALUE = 'FALSE'           WHERE PARAM_NAME = 'SLACK_ENABLED';

-- Pause / resume
-- ALTER TASK OBSERVABILITY.QUERY_ALERTS.TASK_QM_SCAN SUSPEND;
-- ALTER TASK OBSERVABILITY.QUERY_ALERTS.TASK_QM_SCAN RESUME;

-- Act on an alert
-- SELECT SYSTEM$CANCEL_QUERY('<query_id>');
-- SHOW LOCKS IN ACCOUNT;                       -- ACCOUNTADMIN
-- SELECT SYSTEM$ABORT_TRANSACTION(<txn_id>);
