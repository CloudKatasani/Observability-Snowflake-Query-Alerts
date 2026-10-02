/* =============================================================================
   99_teardown.sql                                              run as ACCOUNTADMIN
   Removes everything this project created. The OBSERVABILITY database itself is
   kept (it may host other observability schemas).
   ============================================================================= */
USE ROLE ACCOUNTADMIN;

ALTER TASK IF EXISTS OBSERVABILITY.QUERY_ALERTS.TASK_QM_SCAN SUSPEND;
DROP SCHEMA IF EXISTS OBSERVABILITY.QUERY_ALERTS CASCADE;      -- tables, views, procedures, task, secrets

DROP NOTIFICATION INTEGRATION IF EXISTS QM_EMAIL_INT;
DROP NOTIFICATION INTEGRATION IF EXISTS QM_TEAMS_INT;
DROP NOTIFICATION INTEGRATION IF EXISTS QM_SLACK_INT;
DROP NOTIFICATION INTEGRATION IF EXISTS QM_PAGERDUTY_TRIGGER_INT;
DROP NOTIFICATION INTEGRATION IF EXISTS QM_PAGERDUTY_RESOLVE_INT;

DROP ROLE IF EXISTS OPS_QUERY_MONITOR;
