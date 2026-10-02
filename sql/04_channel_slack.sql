/* =============================================================================
   04_channel_slack.sql                         Channel: SLACK (incoming webhook)
   -----------------------------------------------------------------------------
   Slack side (once): create a Slack app with "Incoming Webhooks" enabled and add
   a webhook to the admin channel. The URL looks like
     https://hooks.slack.com/services/<TEAM_ID>/<WEBHOOK_ID>/<TOKEN>
   Per Snowflake docs, the part after /services/ is the SECRET.
   Section A  ACCOUNTADMIN       secret + webhook integration
   Section B  OPS_QUERY_MONITOR  sender procedure SP_QM_SEND_SLACK
   Section C  OPS_QUERY_MONITOR  enable the channel
   ============================================================================= */

/* ---------- Section A: secret + integration ------------------------------- */
USE ROLE ACCOUNTADMIN;

CREATE OR REPLACE SECRET OBSERVABILITY.QUERY_ALERTS.QM_SLACK_WEBHOOK_SECRET
  TYPE = GENERIC_STRING
  SECRET_STRING = '<TEAM_ID>/<WEBHOOK_ID>/<TOKEN>';                   -- <<< replace

CREATE OR REPLACE NOTIFICATION INTEGRATION QM_SLACK_INT
  TYPE = WEBHOOK
  ENABLED = TRUE
  WEBHOOK_URL = 'https://hooks.slack.com/services/SNOWFLAKE_WEBHOOK_SECRET'
  WEBHOOK_SECRET = OBSERVABILITY.QUERY_ALERTS.QM_SLACK_WEBHOOK_SECRET
  WEBHOOK_BODY_TEMPLATE = '{"text": "SNOWFLAKE_WEBHOOK_MESSAGE"}'
  WEBHOOK_HEADERS = ('Content-Type' = 'application/json')
  COMMENT = 'Query alerts: Slack channel';

GRANT USAGE ON INTEGRATION QM_SLACK_INT TO ROLE OPS_QUERY_MONITOR;
GRANT USAGE ON SECRET OBSERVABILITY.QUERY_ALERTS.QM_SLACK_WEBHOOK_SECRET TO ROLE OPS_QUERY_MONITOR;

/* ---------- Section B: sender --------------------------------------------- */
USE ROLE OPS_QUERY_MONITOR;
USE SCHEMA OBSERVABILITY.QUERY_ALERTS;

CREATE OR REPLACE PROCEDURE OBSERVABILITY.QUERY_ALERTS.SP_QM_SEND_SLACK(P_SUBJECT VARCHAR)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
  v_int   VARCHAR;
  v_max   NUMBER;
  v_total NUMBER;
  v_rows  VARCHAR;
  v_msg   VARCHAR;
BEGIN
  SELECT MAX(IFF(PARAM_NAME = 'SLACK_INTEGRATION', PARAM_VALUE, NULL)),
         COALESCE(MAX(IFF(PARAM_NAME = 'MAX_ROWS_IN_MESSAGE', TRY_TO_NUMBER(PARAM_VALUE), NULL)), 25)
    INTO :v_int, :v_max
    FROM OBSERVABILITY.QUERY_ALERTS.QM_CONFIG;

  SELECT COUNT(*) INTO :v_total FROM OBSERVABILITY.QUERY_ALERTS.QM_CANDIDATES WHERE TO_NOTIFY;
  IF (v_total = 0) THEN
    RETURN 'SLACK:SKIPPED(nothing to send)';
  END IF;

  -- Slack mrkdwn: *bold*, `code`, • bullets
  SELECT LISTAGG('• *' || ALERT_TYPE || '* · ' || TO_VARCHAR(MINUTES) || ' min · ' || COALESCE(WAREHOUSE_NAME, '-') ||
                 ' · ' || COALESCE(USER_NAME, '-') || ' · `' || QUERY_ID || '`' ||
                 COALESCE(' · lock on `' || LOCKED_RESOURCE || '` held by `' || BLOCKER_QUERY_ID || '`', ''), '\n')
           WITHIN GROUP (ORDER BY ALERT_TYPE, MINUTES DESC)
    INTO :v_rows
    FROM (SELECT * FROM OBSERVABILITY.QUERY_ALERTS.QM_CANDIDATES WHERE TO_NOTIFY
          QUALIFY ROW_NUMBER() OVER (ORDER BY MINUTES DESC) <= :v_max);

  v_msg := ':rotating_light: *' || P_SUBJECT || '*\n' || v_rows ||
           IFF(v_total > v_max, '\n_Showing ' || v_max || ' of ' || v_total || ' queries._', '') ||
           '\nCancel: `SELECT SYSTEM$CANCEL_QUERY(''<query_id>'');` · Open alerts: `OBSERVABILITY.QUERY_ALERTS.V_QM_OPEN_ALERTS`';

  CALL SYSTEM$SEND_SNOWFLAKE_NOTIFICATION(
         SNOWFLAKE.NOTIFICATION.TEXT_PLAIN(SNOWFLAKE.NOTIFICATION.SANITIZE_WEBHOOK_CONTENT(:v_msg)),
         SNOWFLAKE.NOTIFICATION.INTEGRATION(:v_int));
  RETURN 'SLACK:OK';
END;
$$;

/* ---------- Section C: enable --------------------------------------------- */
UPDATE OBSERVABILITY.QUERY_ALERTS.QM_CONFIG SET PARAM_VALUE = 'TRUE' WHERE PARAM_NAME = 'SLACK_ENABLED';
