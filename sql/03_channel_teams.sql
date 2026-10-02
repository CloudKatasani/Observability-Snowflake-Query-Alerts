/* =============================================================================
   03_channel_teams.sql                 Channel: MICROSOFT TEAMS (Adaptive Card)
   -----------------------------------------------------------------------------
   Teams side (once): channel ⋯ > Workflows >
     "Post to a channel when a webhook request is received" → copy the URL.
   Per Snowflake docs, store the workflow-id part of the URL as a SECRET and put
   SNOWFLAKE_WEBHOOK_SECRET in its place. Omit any ":443" port.
   Section A  ACCOUNTADMIN       secret + webhook integration
   Section B  OPS_QUERY_MONITOR  sender procedure SP_QM_SEND_TEAMS
   Section C  OPS_QUERY_MONITOR  enable the channel
   ============================================================================= */

/* ---------- Section A: secret + integration ------------------------------- */
USE ROLE ACCOUNTADMIN;

CREATE OR REPLACE SECRET OBSERVABILITY.QUERY_ALERTS.QM_TEAMS_WEBHOOK_SECRET
  TYPE = GENERIC_STRING
  SECRET_STRING = '<workflow-id-from-the-teams-workflow-url>';                      -- <<< replace

CREATE OR REPLACE NOTIFICATION INTEGRATION QM_TEAMS_INT
  TYPE = WEBHOOK
  ENABLED = TRUE
  -- New-format Teams workflow URL (Power Platform). Replace the environment host with yours.
  WEBHOOK_URL = 'https://<your-environment-id>.environment.api.powerplatform.com/powerautomate/automations/direct/workflows/SNOWFLAKE_WEBHOOK_SECRET/triggers/manual/paths/invoke'
  -- Legacy-format alternative:
  -- WEBHOOK_URL = 'https://prod-NN.<region>.logic.azure.com/workflows/SNOWFLAKE_WEBHOOK_SECRET'
  WEBHOOK_SECRET = OBSERVABILITY.QUERY_ALERTS.QM_TEAMS_WEBHOOK_SECRET
  WEBHOOK_BODY_TEMPLATE = '{"type":"message","attachments":[{"contentType":"application/vnd.microsoft.card.adaptive","content":{"$schema":"http://adaptivecards.io/schemas/adaptive-card.json","type":"AdaptiveCard","version":"1.4","body":[{"type":"TextBlock","text":"SNOWFLAKE_WEBHOOK_MESSAGE","wrap":true}]}}]}'
  WEBHOOK_HEADERS = ('Content-Type' = 'application/json')
  COMMENT = 'Query alerts: Microsoft Teams channel';

GRANT USAGE ON INTEGRATION QM_TEAMS_INT TO ROLE OPS_QUERY_MONITOR;
GRANT USAGE ON SECRET OBSERVABILITY.QUERY_ALERTS.QM_TEAMS_WEBHOOK_SECRET TO ROLE OPS_QUERY_MONITOR;

/* ---------- Section B: sender --------------------------------------------- */
USE ROLE OPS_QUERY_MONITOR;
USE SCHEMA OBSERVABILITY.QUERY_ALERTS;

CREATE OR REPLACE PROCEDURE OBSERVABILITY.QUERY_ALERTS.SP_QM_SEND_TEAMS(P_SUBJECT VARCHAR)
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
  SELECT MAX(IFF(PARAM_NAME = 'TEAMS_INTEGRATION', PARAM_VALUE, NULL)),
         COALESCE(MAX(IFF(PARAM_NAME = 'MAX_ROWS_IN_MESSAGE', TRY_TO_NUMBER(PARAM_VALUE), NULL)), 25)
    INTO :v_int, :v_max
    FROM OBSERVABILITY.QUERY_ALERTS.QM_CONFIG;

  SELECT COUNT(*) INTO :v_total FROM OBSERVABILITY.QUERY_ALERTS.QM_CANDIDATES WHERE TO_NOTIFY;
  IF (v_total = 0) THEN
    RETURN 'TEAMS:SKIPPED(nothing to send)';
  END IF;

  -- Adaptive Card TextBlock markdown
  SELECT LISTAGG('- **' || ALERT_TYPE || '** · ' || TO_VARCHAR(MINUTES) || ' min · ' || COALESCE(WAREHOUSE_NAME, '-') ||
                 ' · ' || COALESCE(USER_NAME, '-') || ' · `' || QUERY_ID || '`' ||
                 COALESCE(' · lock on ' || LOCKED_RESOURCE || ' held by `' || BLOCKER_QUERY_ID || '`', ''), '\n')
           WITHIN GROUP (ORDER BY ALERT_TYPE, MINUTES DESC)
    INTO :v_rows
    FROM (SELECT * FROM OBSERVABILITY.QUERY_ALERTS.QM_CANDIDATES WHERE TO_NOTIFY
          QUALIFY ROW_NUMBER() OVER (ORDER BY MINUTES DESC) <= :v_max);

  v_msg := '**' || P_SUBJECT || '**\n\n' || v_rows ||
           IFF(v_total > v_max, '\n\nShowing ' || v_max || ' of ' || v_total || ' queries.', '') ||
           '\n\nCancel: SELECT SYSTEM$CANCEL_QUERY(''<query_id>'') · Open alerts: OBSERVABILITY.QUERY_ALERTS.V_QM_OPEN_ALERTS';

  CALL SYSTEM$SEND_SNOWFLAKE_NOTIFICATION(
         SNOWFLAKE.NOTIFICATION.TEXT_PLAIN(SNOWFLAKE.NOTIFICATION.SANITIZE_WEBHOOK_CONTENT(:v_msg)),
         SNOWFLAKE.NOTIFICATION.INTEGRATION(:v_int));
  RETURN 'TEAMS:OK';
END;
$$;

/* ---------- Section C: enable --------------------------------------------- */
UPDATE OBSERVABILITY.QUERY_ALERTS.QM_CONFIG SET PARAM_VALUE = 'TRUE' WHERE PARAM_NAME = 'TEAMS_ENABLED';
