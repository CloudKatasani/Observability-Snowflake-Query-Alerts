/* =============================================================================
   05_channel_pagerduty.sql            Channel: PAGERDUTY (Events API v2, paging)
   -----------------------------------------------------------------------------
   PagerDuty side (once): Service > Integrations > add "Events API V2" →
   copy the Integration Key (routing_key). Per Snowflake docs the key is the SECRET.

   Paging policy (configurable in QM_CONFIG):
     * only alert types in PAGERDUTY_ALERT_TYPES (default LONG_RUNNING, BLOCKED)
     * only once the query has run / waited ≥ PAGERDUTY_MIN_MINUTES (default 30)
     * ONE incident per account: a fixed dedup_key groups all events, so repeated
       triggers update the open incident instead of creating new ones
     * auto-resolve when no page-eligible query remains (PAGERDUTY_AUTO_RESOLVE)
   Webhook templates are static, so trigger and resolve are two integrations.
   For several Snowflake accounts, give each its own dedup_key (edit below).

   Section A  ACCOUNTADMIN       secret + trigger/resolve integrations
   Section B  OPS_QUERY_MONITOR  sender procedure SP_QM_SEND_PAGERDUTY
   Section C  OPS_QUERY_MONITOR  enable the channel
   ============================================================================= */

/* ---------- Section A: secret + integrations ------------------------------ */
USE ROLE ACCOUNTADMIN;

CREATE OR REPLACE SECRET OBSERVABILITY.QUERY_ALERTS.QM_PAGERDUTY_ROUTING_KEY
  TYPE = GENERIC_STRING
  SECRET_STRING = '<pagerduty-events-v2-integration-key>';                           -- <<< replace

CREATE OR REPLACE NOTIFICATION INTEGRATION QM_PAGERDUTY_TRIGGER_INT
  TYPE = WEBHOOK
  ENABLED = TRUE
  WEBHOOK_URL = 'https://events.pagerduty.com/v2/enqueue'
  WEBHOOK_SECRET = OBSERVABILITY.QUERY_ALERTS.QM_PAGERDUTY_ROUTING_KEY
  WEBHOOK_BODY_TEMPLATE = '{
    "routing_key": "SNOWFLAKE_WEBHOOK_SECRET",
    "event_action": "trigger",
    "dedup_key": "snowflake-query-alerts",
    "payload": {
      "summary": "SNOWFLAKE_WEBHOOK_MESSAGE",
      "source": "Snowflake query alerts",
      "severity": "error",
      "component": "Snowflake",
      "group": "Platform Observability",
      "class": "Query performance"
    }
  }'
  WEBHOOK_HEADERS = ('Content-Type' = 'application/json')
  COMMENT = 'Query alerts: PagerDuty trigger (Events API v2)';

CREATE OR REPLACE NOTIFICATION INTEGRATION QM_PAGERDUTY_RESOLVE_INT
  TYPE = WEBHOOK
  ENABLED = TRUE
  WEBHOOK_URL = 'https://events.pagerduty.com/v2/enqueue'
  WEBHOOK_SECRET = OBSERVABILITY.QUERY_ALERTS.QM_PAGERDUTY_ROUTING_KEY
  WEBHOOK_BODY_TEMPLATE = '{
    "routing_key": "SNOWFLAKE_WEBHOOK_SECRET",
    "event_action": "resolve",
    "dedup_key": "snowflake-query-alerts",
    "payload": {
      "summary": "SNOWFLAKE_WEBHOOK_MESSAGE",
      "source": "Snowflake query alerts",
      "severity": "info"
    }
  }'
  WEBHOOK_HEADERS = ('Content-Type' = 'application/json')
  COMMENT = 'Query alerts: PagerDuty resolve (Events API v2)';

GRANT USAGE ON INTEGRATION QM_PAGERDUTY_TRIGGER_INT TO ROLE OPS_QUERY_MONITOR;
GRANT USAGE ON INTEGRATION QM_PAGERDUTY_RESOLVE_INT TO ROLE OPS_QUERY_MONITOR;
GRANT USAGE ON SECRET OBSERVABILITY.QUERY_ALERTS.QM_PAGERDUTY_ROUTING_KEY TO ROLE OPS_QUERY_MONITOR;

/* ---------- Section B: sender --------------------------------------------- */
USE ROLE OPS_QUERY_MONITOR;
USE SCHEMA OBSERVABILITY.QUERY_ALERTS;

-- P_ACTION = 'TRIGGER' : summarise page-eligible rows (QM_CANDIDATES.PD_ELIGIBLE) — PagerDuty summary ≤ 1024 chars
-- P_ACTION = 'RESOLVE' : close the incident
CREATE OR REPLACE PROCEDURE OBSERVABILITY.QUERY_ALERTS.SP_QM_SEND_PAGERDUTY(P_ACTION VARCHAR, P_SUBJECT VARCHAR)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
  v_trigger_int VARCHAR;
  v_resolve_int VARCHAR;
  v_rows        VARCHAR;
  v_msg         VARCHAR;
BEGIN
  SELECT MAX(IFF(PARAM_NAME = 'PAGERDUTY_TRIGGER_INTEGRATION', PARAM_VALUE, NULL)),
         MAX(IFF(PARAM_NAME = 'PAGERDUTY_RESOLVE_INTEGRATION', PARAM_VALUE, NULL))
    INTO :v_trigger_int, :v_resolve_int
    FROM OBSERVABILITY.QUERY_ALERTS.QM_CONFIG;

  IF (UPPER(P_ACTION) = 'RESOLVE') THEN
    v_msg := LEFT(COALESCE(P_SUBJECT, 'Snowflake query alerts: all page-eligible queries cleared'), 1000);
    CALL SYSTEM$SEND_SNOWFLAKE_NOTIFICATION(
           SNOWFLAKE.NOTIFICATION.TEXT_PLAIN(SNOWFLAKE.NOTIFICATION.SANITIZE_WEBHOOK_CONTENT(:v_msg)),
           SNOWFLAKE.NOTIFICATION.INTEGRATION(:v_resolve_int));
    RETURN 'PAGERDUTY:RESOLVED';
  END IF;

  SELECT LISTAGG(ALERT_TYPE || ' ' || TO_VARCHAR(MINUTES) || 'm ' || COALESCE(WAREHOUSE_NAME, '-') || ' ' ||
                 COALESCE(USER_NAME, '-') || ' ' || QUERY_ID, '; ') WITHIN GROUP (ORDER BY MINUTES DESC)
    INTO :v_rows
    FROM (SELECT * FROM OBSERVABILITY.QUERY_ALERTS.QM_CANDIDATES WHERE PD_ELIGIBLE
          QUALIFY ROW_NUMBER() OVER (ORDER BY MINUTES DESC) <= 5);

  v_msg := LEFT(P_SUBJECT || ' | ' || COALESCE(v_rows, '') || ' | see OBSERVABILITY.QUERY_ALERTS.V_QM_OPEN_ALERTS', 1000);
  CALL SYSTEM$SEND_SNOWFLAKE_NOTIFICATION(
         SNOWFLAKE.NOTIFICATION.TEXT_PLAIN(SNOWFLAKE.NOTIFICATION.SANITIZE_WEBHOOK_CONTENT(:v_msg)),
         SNOWFLAKE.NOTIFICATION.INTEGRATION(:v_trigger_int));
  RETURN 'PAGERDUTY:TRIGGERED';
END;
$$;

/* ---------- Section C: enable --------------------------------------------- */
UPDATE OBSERVABILITY.QUERY_ALERTS.QM_CONFIG SET PARAM_VALUE = 'TRUE' WHERE PARAM_NAME = 'PAGERDUTY_ENABLED';
