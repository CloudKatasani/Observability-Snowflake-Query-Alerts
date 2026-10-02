/* =============================================================================
   01_config_and_log_tables.sql                           run as OPS_QUERY_MONITOR
   -----------------------------------------------------------------------------
   QM_CONFIG         thresholds, exclusions, per-channel switches (no code changes)
   QM_ALERT_LOG      one row per query × alert type — dedupe + audit trail
   QM_CHANNEL_STATE  open/closed state for stateful channels (PagerDuty incident)
   Channels start DISABLED; each channel script (02–05) enables itself on deploy.
   ============================================================================= */
USE ROLE OPS_QUERY_MONITOR;
USE SCHEMA OBSERVABILITY.QUERY_ALERTS;

CREATE TABLE IF NOT EXISTS QM_CONFIG (
  PARAM_NAME  VARCHAR PRIMARY KEY,
  PARAM_VALUE VARCHAR,
  DESCRIPTION VARCHAR
);

MERGE INTO QM_CONFIG t USING (SELECT * FROM VALUES
  -- Detection ------------------------------------------------------------------
  ('LONG_RUNNING_MIN',     '15',    'Alert when a RUNNING query has executed this many minutes (queue/lock wait excluded)'),
  ('QUEUED_MIN',           '5',     'Alert when a query has waited in a warehouse queue this many minutes'),
  ('BLOCKED_MIN',          '5',     'Alert when a query has been blocked by a table lock this many minutes'),
  ('RENOTIFY_MIN',         '30',    'Re-send for the same query/alert type at most every N minutes while it persists'),
  ('EXCLUDED_WAREHOUSES',  '',      'Comma list of warehouses to ignore (e.g. known long batch warehouses)'),
  ('EXCLUDED_USERS',       '',      'Comma list of users to ignore (e.g. service users with expected long jobs)'),
  ('INCLUDE_QUERY_TEXT',   'FALSE', 'TRUE = include first 150 chars of SQL text in notifications (may expose literals)'),
  ('LOCK_DETAILS',         'TRUE',  'TRUE = identify the blocking query via SHOW LOCKS IN ACCOUNT (needs ACCOUNTADMIN; skipped otherwise)'),
  ('MAX_ROWS_IN_MESSAGE',  '25',    'Cap rows per digest (e-mail / Teams / Slack)'),
  -- E-mail ---------------------------------------------------------------------
  ('EMAIL_ENABLED',        'FALSE', 'Set TRUE by 02_channel_email.sql'),
  ('EMAIL_INTEGRATION',    'QM_EMAIL_INT', 'E-mail notification integration'),
  ('EMAIL_RECIPIENTS',     'snowflake-admins@client.com', 'Comma list; must be in the integration ALLOWED_RECIPIENTS'),
  -- Microsoft Teams --------------------------------------------------------------
  ('TEAMS_ENABLED',        'FALSE', 'Set TRUE by 03_channel_teams.sql'),
  ('TEAMS_INTEGRATION',    'QM_TEAMS_INT', 'Teams (Power Automate Workflows) webhook integration'),
  -- Slack --------------------------------------------------------------------------
  ('SLACK_ENABLED',        'FALSE', 'Set TRUE by 04_channel_slack.sql'),
  ('SLACK_INTEGRATION',    'QM_SLACK_INT', 'Slack incoming-webhook integration'),
  -- PagerDuty ----------------------------------------------------------------------
  ('PAGERDUTY_ENABLED',             'FALSE', 'Set TRUE by 05_channel_pagerduty.sql'),
  ('PAGERDUTY_TRIGGER_INTEGRATION', 'QM_PAGERDUTY_TRIGGER_INT', 'Events API v2 integration with event_action = trigger'),
  ('PAGERDUTY_RESOLVE_INTEGRATION', 'QM_PAGERDUTY_RESOLVE_INT', 'Events API v2 integration with event_action = resolve'),
  ('PAGERDUTY_ALERT_TYPES',         'LONG_RUNNING,BLOCKED', 'Alert types that page on-call (QUEUED usually goes to chat only)'),
  ('PAGERDUTY_MIN_MINUTES',         '30',    'Page only when the query has run / waited at least this long (escalation threshold)'),
  ('PAGERDUTY_AUTO_RESOLVE',        'TRUE',  'TRUE = resolve the PagerDuty incident when no page-eligible query remains')
) s(PARAM_NAME, PARAM_VALUE, DESCRIPTION)
ON t.PARAM_NAME = s.PARAM_NAME
WHEN NOT MATCHED THEN INSERT VALUES (s.PARAM_NAME, s.PARAM_VALUE, s.DESCRIPTION);

CREATE TABLE IF NOT EXISTS QM_ALERT_LOG (
  QUERY_ID            VARCHAR       NOT NULL,
  ALERT_TYPE          VARCHAR       NOT NULL,   -- LONG_RUNNING | QUEUED | BLOCKED
  WAREHOUSE_NAME      VARCHAR,
  WAREHOUSE_SIZE      VARCHAR,
  USER_NAME           VARCHAR,
  ROLE_NAME           VARCHAR,
  DATABASE_NAME       VARCHAR,
  QUERY_TYPE          VARCHAR,
  QUERY_TAG           VARCHAR,
  QUERY_START_TIME    TIMESTAMP_LTZ,
  FIRST_DETECTED_AT   TIMESTAMP_LTZ,
  LAST_SEEN_AT        TIMESTAMP_LTZ,
  LAST_NOTIFIED_AT    TIMESTAMP_LTZ,         -- chat/e-mail channels
  NOTIFY_COUNT        NUMBER,
  PAGERDUTY_TRIGGERED_AT TIMESTAMP_LTZ,      -- last time this query was included in a PagerDuty trigger
  MAX_MINUTES         NUMBER(10,1),          -- longest observed execution / wait minutes
  LOCKED_RESOURCE     VARCHAR,
  BLOCKER_QUERY_ID    VARCHAR,
  BLOCKER_TXN_ID      VARCHAR,
  LAST_CHANNEL_STATUS VARCHAR,
  RESOLVED_AT         TIMESTAMP_LTZ,         -- query finished, started executing, or got its lock
  PRIMARY KEY (QUERY_ID, ALERT_TYPE)
);

CREATE TABLE IF NOT EXISTS QM_CHANNEL_STATE (
  CHANNEL     VARCHAR PRIMARY KEY,
  STATE       VARCHAR,          -- OPEN | CLOSED
  UPDATED_AT  TIMESTAMP_LTZ,
  DETAIL      VARCHAR
);
MERGE INTO QM_CHANNEL_STATE t USING (SELECT 'PAGERDUTY' AS CHANNEL) s ON t.CHANNEL = s.CHANNEL
WHEN NOT MATCHED THEN INSERT (CHANNEL, STATE, UPDATED_AT) VALUES ('PAGERDUTY', 'CLOSED', CURRENT_TIMESTAMP());
