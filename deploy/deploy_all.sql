-- =============================================================================
-- deploy_all.sql — run every script in order with SnowSQL (!source) from the repo root:
--   snowsql -a <account> -u <admin_user> -f deploy/deploy_all.sql
-- Snowflake CLI alternative (one file at a time, same order):
--   for f in sql/0*.sql; do snow sql -f "$f"; done
-- The deploying user needs ACCOUNTADMIN; scripts switch roles themselves.
-- Comment out the channels you do not use (each channel is independent).
-- Edit the <<< replace placeholders in 02–05 first.
-- =============================================================================
!set exit_on_error=true

!source sql/00_setup_role_database.sql
!source sql/01_config_and_log_tables.sql

-- Notification channels (deploy any subset)
!source sql/02_channel_email.sql
!source sql/03_channel_teams.sql
!source sql/04_channel_slack.sql
!source sql/05_channel_pagerduty.sql

!source sql/06_procedure_scan.sql
!source sql/08_views.sql
!source sql/09_test_and_operate.sql

-- Start the schedule last, after the channel test has passed:
--   CALL OBSERVABILITY.QUERY_ALERTS.SP_QM_TEST_CHANNELS();
!source sql/07_task_schedule.sql
