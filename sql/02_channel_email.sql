/* =============================================================================
   02_channel_email.sql                              Channel: E-MAIL (HTML digest)
   -----------------------------------------------------------------------------
   Section A  ACCOUNTADMIN       notification integration
   Section B  OPS_QUERY_MONITOR  sender procedure SP_QM_SEND_EMAIL
   Section C  OPS_QUERY_MONITOR  enable the channel in QM_CONFIG
   Recipients must be e-mail addresses of users in this Snowflake account who
   have VERIFIED their e-mail. A Teams/Slack channel e-mail address also works.
   ============================================================================= */

/* ---------- Section A: integration ---------------------------------------- */
USE ROLE ACCOUNTADMIN;

CREATE NOTIFICATION INTEGRATION IF NOT EXISTS QM_EMAIL_INT
  TYPE = EMAIL
  ENABLED = TRUE
  ALLOWED_RECIPIENTS = ('snowflake-admins@client.com', 'dba.oncall@client.com')     -- <<< replace
  COMMENT = 'Query alerts: e-mail to Snowflake Admin team';

GRANT USAGE ON INTEGRATION QM_EMAIL_INT TO ROLE OPS_QUERY_MONITOR;

/* ---------- Section B: sender --------------------------------------------- */
USE ROLE OPS_QUERY_MONITOR;
USE SCHEMA OBSERVABILITY.QUERY_ALERTS;

-- Reads the session temp table QM_CANDIDATES (rows with TO_NOTIFY = TRUE) built by SP_QM_SCAN.
CREATE OR REPLACE PROCEDURE OBSERVABILITY.QUERY_ALERTS.SP_QM_SEND_EMAIL(P_SUBJECT VARCHAR)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
  v_int        VARCHAR;
  v_to         VARCHAR;
  v_max        NUMBER;
  v_long_min   VARCHAR;
  v_queue_min  VARCHAR;
  v_block_min  VARCHAR;
  v_total      NUMBER;
  v_rows       VARCHAR;
  v_html       VARCHAR;
BEGIN
  SELECT MAX(IFF(PARAM_NAME = 'EMAIL_INTEGRATION', PARAM_VALUE, NULL)),
         MAX(IFF(PARAM_NAME = 'EMAIL_RECIPIENTS',  PARAM_VALUE, NULL)),
         COALESCE(MAX(IFF(PARAM_NAME = 'MAX_ROWS_IN_MESSAGE', TRY_TO_NUMBER(PARAM_VALUE), NULL)), 25),
         MAX(IFF(PARAM_NAME = 'LONG_RUNNING_MIN', PARAM_VALUE, NULL)),
         MAX(IFF(PARAM_NAME = 'QUEUED_MIN',       PARAM_VALUE, NULL)),
         MAX(IFF(PARAM_NAME = 'BLOCKED_MIN',      PARAM_VALUE, NULL))
    INTO :v_int, :v_to, :v_max, :v_long_min, :v_queue_min, :v_block_min
    FROM OBSERVABILITY.QUERY_ALERTS.QM_CONFIG;

  SELECT COUNT(*) INTO :v_total FROM OBSERVABILITY.QUERY_ALERTS.QM_CANDIDATES WHERE TO_NOTIFY;
  IF (v_total = 0) THEN
    RETURN 'EMAIL:SKIPPED(nothing to send)';
  END IF;

  SELECT LISTAGG('<tr><td><b>' || ALERT_TYPE || '</b></td><td>' || TO_VARCHAR(MINUTES) || '</td><td>' ||
                 COALESCE(WAREHOUSE_NAME, '') || ' (' || COALESCE(WAREHOUSE_SIZE, '') || ')</td><td>' ||
                 COALESCE(USER_NAME, '') || '</td><td>' || COALESCE(ROLE_NAME, '') ||
                 '</td><td style="font-family:monospace">' || QUERY_ID || '</td><td>' ||
                 COALESCE('Lock on ' || LOCKED_RESOURCE || ' held by query ' || BLOCKER_QUERY_ID || ' (txn ' || BLOCKER_TXN_ID || ')', '') ||
                 COALESCE('<br/><i>' || REPLACE(REPLACE(REPLACE(QUERY_TEXT_SNIPPET, '&', '&amp;'), '<', '&lt;'), '>', '&gt;') || '</i>', '') ||
                 '</td></tr>', '') WITHIN GROUP (ORDER BY ALERT_TYPE, MINUTES DESC)
    INTO :v_rows
    FROM (SELECT * FROM OBSERVABILITY.QUERY_ALERTS.QM_CANDIDATES WHERE TO_NOTIFY
          QUALIFY ROW_NUMBER() OVER (ORDER BY MINUTES DESC) <= :v_max);

  v_html := '<p><b>' || P_SUBJECT || '</b><br/>Detected at ' || TO_VARCHAR(CURRENT_TIMESTAMP(), 'YYYY-MM-DD HH24:MI TZH:TZM') ||
            ' · thresholds: running ≥ ' || v_long_min || ' min, queued ≥ ' || v_queue_min || ' min, blocked ≥ ' || v_block_min || ' min</p>' ||
            '<table border="1" cellpadding="4" cellspacing="0" style="border-collapse:collapse;font-family:Calibri,Arial;font-size:12px">' ||
            '<tr style="background:#12446E;color:#fff"><th>Type</th><th>Minutes</th><th>Warehouse</th><th>User</th><th>Role</th><th>Query ID</th><th>Details</th></tr>' ||
            v_rows || '</table>' ||
            '<p>Investigate: Snowsight » Monitoring » Query History (filter by Query ID).<br/>' ||
            'Cancel: <code>SELECT SYSTEM$CANCEL_QUERY(''&lt;query_id&gt;'');</code> · ' ||
            'Release a lock: <code>SELECT SYSTEM$ABORT_TRANSACTION(&lt;txn_id&gt;);</code><br/>' ||
            'Open alerts: <code>SELECT * FROM OBSERVABILITY.QUERY_ALERTS.V_QM_OPEN_ALERTS;</code></p>' ||
            IFF(v_total > v_max, '<p>Showing ' || v_max || ' of ' || v_total || ' queries.</p>', '');

  CALL SYSTEM$SEND_EMAIL(:v_int, :v_to, :P_SUBJECT, :v_html, 'text/html');
  RETURN 'EMAIL:OK';
END;
$$;

/* ---------- Section C: enable --------------------------------------------- */
UPDATE OBSERVABILITY.QUERY_ALERTS.QM_CONFIG SET PARAM_VALUE = 'TRUE' WHERE PARAM_NAME = 'EMAIL_ENABLED';
-- UPDATE OBSERVABILITY.QUERY_ALERTS.QM_CONFIG SET PARAM_VALUE = 'snowflake-admins@client.com,dba.oncall@client.com' WHERE PARAM_NAME = 'EMAIL_RECIPIENTS';
