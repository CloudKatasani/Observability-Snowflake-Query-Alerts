/* =============================================================================
   06_procedure_scan.sql                                  run as OPS_QUERY_MONITOR
   -----------------------------------------------------------------------------
   SP_QM_SCAN — detection, de-duplication, channel dispatch and logging.
     1. read QM_CONFIG
     2. collect in-flight queries per warehouse from
        INFORMATION_SCHEMA.QUERY_HISTORY_BY_WAREHOUSE()  (real time)
     3. classify:  LONG_RUNNING  RUNNING, executing ≥ LONG_RUNNING_MIN
                   QUEUED        QUEUED / RESUMING_WAREHOUSE ≥ QUEUED_MIN
                   BLOCKED       BLOCKED (table lock wait)   ≥ BLOCKED_MIN
     4. lock holder via SHOW LOCKS IN ACCOUNT (best effort)
     5. TO_NOTIFY  : new, or still open past RENOTIFY_MIN      → e-mail, Teams, Slack
        PD_NOTIFY  : page-eligible and not paged within RENOTIFY_MIN → PagerDuty
     6. dispatch to each ENABLED channel; one failing channel never blocks another
     7. upsert QM_ALERT_LOG, resolve cleared alerts, auto-resolve PagerDuty
   Channel senders (02–05) read the session temp table QM_CANDIDATES.
   ============================================================================= */
USE ROLE OPS_QUERY_MONITOR;
USE SCHEMA OBSERVABILITY.QUERY_ALERTS;

CREATE OR REPLACE PROCEDURE OBSERVABILITY.QUERY_ALERTS.SP_QM_SCAN()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
  -- config
  v_long_min     NUMBER;
  v_queue_min    NUMBER;
  v_block_min    NUMBER;
  v_renotify_min NUMBER;
  v_excl_wh      VARCHAR;
  v_excl_users   VARCHAR;
  v_incl_text    BOOLEAN;
  v_lock_details BOOLEAN;
  v_email_on     BOOLEAN;
  v_teams_on     BOOLEAN;
  v_slack_on     BOOLEAN;
  v_pd_on        BOOLEAN;
  v_pd_types     VARCHAR;
  v_pd_min       NUMBER;
  v_pd_autores   BOOLEAN;
  -- working
  v_wh           VARCHAR;
  v_n_long       NUMBER DEFAULT 0;
  v_n_queued     NUMBER DEFAULT 0;
  v_n_blocked    NUMBER DEFAULT 0;
  v_n_total      NUMBER DEFAULT 0;
  v_pd_notify    NUMBER DEFAULT 0;
  v_pd_open_now  NUMBER DEFAULT 0;
  v_pd_state     VARCHAR;
  v_subject      VARCHAR;
  v_pd_subject   VARCHAR;
  v_ret          VARCHAR;
  v_status       VARCHAR DEFAULT '';
  v_pd_status    VARCHAR DEFAULT '';
  v_note         VARCHAR DEFAULT '';
BEGIN
  /* 1. configuration ------------------------------------------------------- */
  SELECT MAX(IFF(PARAM_NAME = 'LONG_RUNNING_MIN',       TRY_TO_NUMBER(PARAM_VALUE), NULL)),
         MAX(IFF(PARAM_NAME = 'QUEUED_MIN',             TRY_TO_NUMBER(PARAM_VALUE), NULL)),
         MAX(IFF(PARAM_NAME = 'BLOCKED_MIN',            TRY_TO_NUMBER(PARAM_VALUE), NULL)),
         MAX(IFF(PARAM_NAME = 'RENOTIFY_MIN',           TRY_TO_NUMBER(PARAM_VALUE), NULL)),
         UPPER(REPLACE(COALESCE(MAX(IFF(PARAM_NAME = 'EXCLUDED_WAREHOUSES', PARAM_VALUE, NULL)), ''), ' ', '')),
         UPPER(REPLACE(COALESCE(MAX(IFF(PARAM_NAME = 'EXCLUDED_USERS',      PARAM_VALUE, NULL)), ''), ' ', '')),
         COALESCE(TRY_TO_BOOLEAN(MAX(IFF(PARAM_NAME = 'INCLUDE_QUERY_TEXT',     PARAM_VALUE, NULL))), FALSE),
         COALESCE(TRY_TO_BOOLEAN(MAX(IFF(PARAM_NAME = 'LOCK_DETAILS',           PARAM_VALUE, NULL))), FALSE),
         COALESCE(TRY_TO_BOOLEAN(MAX(IFF(PARAM_NAME = 'EMAIL_ENABLED',          PARAM_VALUE, NULL))), FALSE),
         COALESCE(TRY_TO_BOOLEAN(MAX(IFF(PARAM_NAME = 'TEAMS_ENABLED',          PARAM_VALUE, NULL))), FALSE),
         COALESCE(TRY_TO_BOOLEAN(MAX(IFF(PARAM_NAME = 'SLACK_ENABLED',          PARAM_VALUE, NULL))), FALSE),
         COALESCE(TRY_TO_BOOLEAN(MAX(IFF(PARAM_NAME = 'PAGERDUTY_ENABLED',      PARAM_VALUE, NULL))), FALSE),
         UPPER(REPLACE(COALESCE(MAX(IFF(PARAM_NAME = 'PAGERDUTY_ALERT_TYPES', PARAM_VALUE, NULL)), ''), ' ', '')),
         COALESCE(MAX(IFF(PARAM_NAME = 'PAGERDUTY_MIN_MINUTES', TRY_TO_NUMBER(PARAM_VALUE), NULL)), 30),
         COALESCE(TRY_TO_BOOLEAN(MAX(IFF(PARAM_NAME = 'PAGERDUTY_AUTO_RESOLVE', PARAM_VALUE, NULL))), TRUE)
    INTO :v_long_min, :v_queue_min, :v_block_min, :v_renotify_min, :v_excl_wh, :v_excl_users, :v_incl_text,
         :v_lock_details, :v_email_on, :v_teams_on, :v_slack_on, :v_pd_on, :v_pd_types, :v_pd_min, :v_pd_autores
    FROM OBSERVABILITY.QUERY_ALERTS.QM_CONFIG;

  /* 2. collect in-flight queries per warehouse ----------------------------- */
  CREATE OR REPLACE TEMPORARY TABLE OBSERVABILITY.QUERY_ALERTS.QM_CANDIDATES (
    QUERY_ID VARCHAR, ALERT_TYPE VARCHAR, EXECUTION_STATUS VARCHAR, MINUTES NUMBER(10,1),
    WAREHOUSE_NAME VARCHAR, WAREHOUSE_SIZE VARCHAR, USER_NAME VARCHAR, ROLE_NAME VARCHAR,
    DATABASE_NAME VARCHAR, QUERY_TYPE VARCHAR, QUERY_TAG VARCHAR, QUERY_START_TIME TIMESTAMP_LTZ,
    QUERY_TEXT_SNIPPET VARCHAR, LOCKED_RESOURCE VARCHAR, BLOCKER_QUERY_ID VARCHAR, BLOCKER_TXN_ID VARCHAR,
    TO_NOTIFY BOOLEAN DEFAULT FALSE, PD_ELIGIBLE BOOLEAN DEFAULT FALSE, PD_NOTIFY BOOLEAN DEFAULT FALSE);

  SHOW WAREHOUSES;
  LET rs_wh RESULTSET := (
    SELECT "name" AS WH FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
     WHERE NOT ARRAY_CONTAINS(UPPER("name")::VARIANT, SPLIT(:v_excl_wh, ',')));
  LET c_wh CURSOR FOR rs_wh;
  FOR w IN c_wh DO
    v_wh := w.WH;
    BEGIN
      INSERT INTO OBSERVABILITY.QUERY_ALERTS.QM_CANDIDATES
        (QUERY_ID, ALERT_TYPE, EXECUTION_STATUS, MINUTES, WAREHOUSE_NAME, WAREHOUSE_SIZE, USER_NAME, ROLE_NAME,
         DATABASE_NAME, QUERY_TYPE, QUERY_TAG, QUERY_START_TIME, QUERY_TEXT_SNIPPET)
      SELECT * FROM (
        SELECT
          q.QUERY_ID,
          CASE
            WHEN UPPER(q.EXECUTION_STATUS) = 'RUNNING'                          THEN 'LONG_RUNNING'
            WHEN UPPER(q.EXECUTION_STATUS) IN ('QUEUED', 'RESUMING_WAREHOUSE')  THEN 'QUEUED'
            WHEN UPPER(q.EXECUTION_STATUS) = 'BLOCKED'                          THEN 'BLOCKED'
          END                                                                    AS ALERT_TYPE,
          UPPER(q.EXECUTION_STATUS)                                              AS EXECUTION_STATUS,
          -- RUNNING: elapsed minus time already spent queued / blocked; others: elapsed wait
          ROUND(IFF(UPPER(q.EXECUTION_STATUS) = 'RUNNING',
                    DATEDIFF('second', q.START_TIME, CURRENT_TIMESTAMP())
                      - (COALESCE(q.QUEUED_PROVISIONING_TIME, 0) + COALESCE(q.QUEUED_REPAIR_TIME, 0)
                         + COALESCE(q.QUEUED_OVERLOAD_TIME, 0) + COALESCE(q.TRANSACTION_BLOCKED_TIME, 0)) / 1000,
                    DATEDIFF('second', q.START_TIME, CURRENT_TIMESTAMP())) / 60, 1) AS MINUTES,
          q.WAREHOUSE_NAME, q.WAREHOUSE_SIZE, q.USER_NAME, q.ROLE_NAME, q.DATABASE_NAME, q.QUERY_TYPE,
          NULLIF(q.QUERY_TAG, ''), q.START_TIME,
          IFF(:v_incl_text, LEFT(REGEXP_REPLACE(q.QUERY_TEXT, '\\s+', ' '), 150), NULL)
        FROM TABLE(OBSERVABILITY.INFORMATION_SCHEMA.QUERY_HISTORY_BY_WAREHOUSE(
                     WAREHOUSE_NAME => :v_wh, RESULT_LIMIT => 10000)) q
        WHERE UPPER(q.EXECUTION_STATUS) IN ('RUNNING', 'QUEUED', 'RESUMING_WAREHOUSE', 'BLOCKED')
          AND NOT ARRAY_CONTAINS(UPPER(q.USER_NAME)::VARIANT, SPLIT(:v_excl_users, ','))
      )
      WHERE (ALERT_TYPE = 'LONG_RUNNING' AND MINUTES >= :v_long_min)
         OR (ALERT_TYPE = 'QUEUED'       AND MINUTES >= :v_queue_min)
         OR (ALERT_TYPE = 'BLOCKED'      AND MINUTES >= :v_block_min);
    EXCEPTION
      WHEN OTHER THEN v_note := v_note || ' [' || v_wh || ': ' || LEFT(SQLERRM, 120) || ']';
    END;
  END FOR;

  /* 3. lock holder for blocked queries (best effort) ------------------------ */
  SELECT COUNT_IF(ALERT_TYPE = 'BLOCKED') INTO :v_n_blocked FROM OBSERVABILITY.QUERY_ALERTS.QM_CANDIDATES;
  IF (v_lock_details AND v_n_blocked > 0) THEN
    BEGIN
      SHOW LOCKS IN ACCOUNT;
      CREATE OR REPLACE TEMPORARY TABLE OBSERVABILITY.QUERY_ALERTS.QM_LOCKS AS
        SELECT "resource" AS RESOURCE, "transaction"::VARCHAR AS TXN_ID, UPPER("status") AS STATUS, "query_id" AS QUERY_ID
          FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));
      UPDATE OBSERVABILITY.QUERY_ALERTS.QM_CANDIDATES c
         SET LOCKED_RESOURCE = x.RESOURCE, BLOCKER_QUERY_ID = x.HOLDER_QUERY_ID, BLOCKER_TXN_ID = x.HOLDER_TXN_ID
        FROM (SELECT w.QUERY_ID AS WAITING_QUERY_ID,
                     MIN(w.RESOURCE) AS RESOURCE,
                     MIN(h.QUERY_ID) AS HOLDER_QUERY_ID,
                     MIN(h.TXN_ID)   AS HOLDER_TXN_ID
                FROM OBSERVABILITY.QUERY_ALERTS.QM_LOCKS w
                JOIN OBSERVABILITY.QUERY_ALERTS.QM_LOCKS h
                  ON h.RESOURCE = w.RESOURCE AND h.STATUS = 'HOLDING'
               WHERE w.STATUS = 'WAITING'
               GROUP BY w.QUERY_ID) x
       WHERE c.ALERT_TYPE = 'BLOCKED' AND c.QUERY_ID = x.WAITING_QUERY_ID;
    EXCEPTION
      WHEN OTHER THEN v_note := v_note || ' [lock details unavailable: ' || LEFT(SQLERRM, 120) || ']';
    END;
  END IF;

  /* 4. what to notify ----------------------------------------------------------- */
  -- chat / e-mail: new, or still open and past the re-notify window
  UPDATE OBSERVABILITY.QUERY_ALERTS.QM_CANDIDATES c
     SET TO_NOTIFY = TRUE
   WHERE NOT EXISTS (
           SELECT 1 FROM OBSERVABILITY.QUERY_ALERTS.QM_ALERT_LOG l
            WHERE l.QUERY_ID = c.QUERY_ID AND l.ALERT_TYPE = c.ALERT_TYPE
              AND l.LAST_NOTIFIED_AT > DATEADD('minute', -1 * :v_renotify_min, CURRENT_TIMESTAMP()));

  -- PagerDuty: escalation threshold + own re-trigger window
  UPDATE OBSERVABILITY.QUERY_ALERTS.QM_CANDIDATES
     SET PD_ELIGIBLE = TRUE
   WHERE ARRAY_CONTAINS(ALERT_TYPE::VARIANT, SPLIT(:v_pd_types, ','))
     AND MINUTES >= :v_pd_min;
  UPDATE OBSERVABILITY.QUERY_ALERTS.QM_CANDIDATES c
     SET PD_NOTIFY = TRUE
   WHERE c.PD_ELIGIBLE
     AND NOT EXISTS (
           SELECT 1 FROM OBSERVABILITY.QUERY_ALERTS.QM_ALERT_LOG l
            WHERE l.QUERY_ID = c.QUERY_ID AND l.ALERT_TYPE = c.ALERT_TYPE
              AND l.PAGERDUTY_TRIGGERED_AT > DATEADD('minute', -1 * :v_renotify_min, CURRENT_TIMESTAMP()));

  SELECT COUNT_IF(TO_NOTIFY AND ALERT_TYPE = 'LONG_RUNNING'), COUNT_IF(TO_NOTIFY AND ALERT_TYPE = 'QUEUED'),
         COUNT_IF(TO_NOTIFY AND ALERT_TYPE = 'BLOCKED'),      COUNT_IF(TO_NOTIFY),
         COUNT_IF(PD_NOTIFY),                                 COUNT_IF(PD_ELIGIBLE)
    INTO :v_n_long, :v_n_queued, :v_n_blocked, :v_n_total, :v_pd_notify, :v_pd_open_now
    FROM OBSERVABILITY.QUERY_ALERTS.QM_CANDIDATES;

  /* 5. dispatch: e-mail / Teams / Slack (digest) ------------------------------- */
  IF (v_n_total > 0) THEN
    v_subject := '[Snowflake ' || CURRENT_ACCOUNT() || '] ' || v_n_long || ' long-running, ' ||
                 v_n_queued || ' queued, ' || v_n_blocked || ' lock-blocked queries';

    IF (v_email_on) THEN
      BEGIN
        CALL OBSERVABILITY.QUERY_ALERTS.SP_QM_SEND_EMAIL(:v_subject) INTO :v_ret;
        v_status := v_status || v_ret || ' ';
      EXCEPTION WHEN OTHER THEN v_status := v_status || 'EMAIL:FAILED(' || LEFT(SQLERRM, 80) || ') ';
      END;
    END IF;

    IF (v_teams_on) THEN
      BEGIN
        CALL OBSERVABILITY.QUERY_ALERTS.SP_QM_SEND_TEAMS(:v_subject) INTO :v_ret;
        v_status := v_status || v_ret || ' ';
      EXCEPTION WHEN OTHER THEN v_status := v_status || 'TEAMS:FAILED(' || LEFT(SQLERRM, 80) || ') ';
      END;
    END IF;

    IF (v_slack_on) THEN
      BEGIN
        CALL OBSERVABILITY.QUERY_ALERTS.SP_QM_SEND_SLACK(:v_subject) INTO :v_ret;
        v_status := v_status || v_ret || ' ';
      EXCEPTION WHEN OTHER THEN v_status := v_status || 'SLACK:FAILED(' || LEFT(SQLERRM, 80) || ') ';
      END;
    END IF;
  END IF;

  /* 6. dispatch: PagerDuty (trigger / auto-resolve) -------------------------- */
  IF (v_pd_on) THEN
    SELECT STATE INTO :v_pd_state FROM OBSERVABILITY.QUERY_ALERTS.QM_CHANNEL_STATE WHERE CHANNEL = 'PAGERDUTY';
    IF (v_pd_notify > 0) THEN
      v_pd_subject := '[Snowflake ' || CURRENT_ACCOUNT() || '] ' || v_pd_open_now ||
                      ' queries running/blocked ≥ ' || v_pd_min || ' min';
      BEGIN
        CALL OBSERVABILITY.QUERY_ALERTS.SP_QM_SEND_PAGERDUTY('TRIGGER', :v_pd_subject) INTO :v_pd_status;
        UPDATE OBSERVABILITY.QUERY_ALERTS.QM_CHANNEL_STATE
           SET STATE = 'OPEN', UPDATED_AT = CURRENT_TIMESTAMP(), DETAIL = :v_pd_subject
         WHERE CHANNEL = 'PAGERDUTY';
      EXCEPTION WHEN OTHER THEN v_pd_status := 'PAGERDUTY:FAILED(' || LEFT(SQLERRM, 80) || ')';
      END;
    ELSEIF (v_pd_open_now = 0 AND v_pd_state = 'OPEN' AND v_pd_autores) THEN
      BEGIN
        CALL OBSERVABILITY.QUERY_ALERTS.SP_QM_SEND_PAGERDUTY('RESOLVE',
               '[Snowflake ' || CURRENT_ACCOUNT() || '] all page-eligible queries cleared') INTO :v_pd_status;
        UPDATE OBSERVABILITY.QUERY_ALERTS.QM_CHANNEL_STATE
           SET STATE = 'CLOSED', UPDATED_AT = CURRENT_TIMESTAMP(), DETAIL = 'auto-resolved'
         WHERE CHANNEL = 'PAGERDUTY';
      EXCEPTION WHEN OTHER THEN v_pd_status := 'PAGERDUTY:RESOLVE_FAILED(' || LEFT(SQLERRM, 80) || ')';
      END;
    END IF;
    v_status := v_status || v_pd_status;
  END IF;

  /* 7. log ---------------------------------------------------------------------- */
  MERGE INTO OBSERVABILITY.QUERY_ALERTS.QM_ALERT_LOG l
  USING OBSERVABILITY.QUERY_ALERTS.QM_CANDIDATES c
     ON l.QUERY_ID = c.QUERY_ID AND l.ALERT_TYPE = c.ALERT_TYPE
  WHEN MATCHED THEN UPDATE SET
       LAST_SEEN_AT           = CURRENT_TIMESTAMP(),
       MAX_MINUTES            = GREATEST(COALESCE(l.MAX_MINUTES, 0), c.MINUTES),
       LOCKED_RESOURCE        = COALESCE(c.LOCKED_RESOURCE, l.LOCKED_RESOURCE),
       BLOCKER_QUERY_ID       = COALESCE(c.BLOCKER_QUERY_ID, l.BLOCKER_QUERY_ID),
       BLOCKER_TXN_ID         = COALESCE(c.BLOCKER_TXN_ID, l.BLOCKER_TXN_ID),
       LAST_NOTIFIED_AT       = IFF(c.TO_NOTIFY, CURRENT_TIMESTAMP(), l.LAST_NOTIFIED_AT),
       NOTIFY_COUNT           = l.NOTIFY_COUNT + IFF(c.TO_NOTIFY, 1, 0),
       PAGERDUTY_TRIGGERED_AT = IFF(c.PD_NOTIFY AND :v_pd_status = 'PAGERDUTY:TRIGGERED', CURRENT_TIMESTAMP(), l.PAGERDUTY_TRIGGERED_AT),
       LAST_CHANNEL_STATUS    = IFF(c.TO_NOTIFY OR c.PD_NOTIFY, :v_status, l.LAST_CHANNEL_STATUS),
       RESOLVED_AT            = NULL
  WHEN NOT MATCHED THEN INSERT
       (QUERY_ID, ALERT_TYPE, WAREHOUSE_NAME, WAREHOUSE_SIZE, USER_NAME, ROLE_NAME, DATABASE_NAME, QUERY_TYPE, QUERY_TAG,
        QUERY_START_TIME, FIRST_DETECTED_AT, LAST_SEEN_AT, LAST_NOTIFIED_AT, NOTIFY_COUNT, PAGERDUTY_TRIGGERED_AT,
        MAX_MINUTES, LOCKED_RESOURCE, BLOCKER_QUERY_ID, BLOCKER_TXN_ID, LAST_CHANNEL_STATUS)
  VALUES
       (c.QUERY_ID, c.ALERT_TYPE, c.WAREHOUSE_NAME, c.WAREHOUSE_SIZE, c.USER_NAME, c.ROLE_NAME, c.DATABASE_NAME, c.QUERY_TYPE, c.QUERY_TAG,
        c.QUERY_START_TIME, CURRENT_TIMESTAMP(), CURRENT_TIMESTAMP(), CURRENT_TIMESTAMP(), 1,
        IFF(c.PD_NOTIFY AND :v_pd_status = 'PAGERDUTY:TRIGGERED', CURRENT_TIMESTAMP(), NULL),
        c.MINUTES, c.LOCKED_RESOURCE, c.BLOCKER_QUERY_ID, c.BLOCKER_TXN_ID, :v_status);

  -- close alerts whose query finished, started executing, or got its lock
  UPDATE OBSERVABILITY.QUERY_ALERTS.QM_ALERT_LOG l
     SET RESOLVED_AT = CURRENT_TIMESTAMP()
   WHERE l.RESOLVED_AT IS NULL
     AND NOT EXISTS (SELECT 1 FROM OBSERVABILITY.QUERY_ALERTS.QM_CANDIDATES c
                      WHERE c.QUERY_ID = l.QUERY_ID AND c.ALERT_TYPE = l.ALERT_TYPE);

  RETURN 'notified=' || v_n_total || ' (long=' || v_n_long || ', queued=' || v_n_queued || ', blocked=' || v_n_blocked ||
         ') paged=' || v_pd_notify || ' ' || v_status || v_note;
END;
$$;
