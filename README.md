# Observability: Snowflake Real-Time Query Alerts

Native Snowflake alerting for **long-running**, **queued** and **lock-blocked** queries. Notifications go to **E-mail**, **Microsoft Teams**, **Slack** and **PagerDuty**.

| Alert | Default trigger |
|---|---|
| 🐢 `LONG_RUNNING` | Query **executing** ≥ 15 min |
| ⏳ `QUEUED` | Query **waiting for warehouse capacity** ≥ 5 min |
| 🔒 `BLOCKED` | Query **waiting on a table lock** ≥ 5 min. The message names the locked table and the blocking query when available. |

- **Speed:** detection within about 1 minute (serverless task plus real-time `INFORMATION_SCHEMA` query history).
- **No noise:** one digest per run, and each query is repeated at most every 30 minutes.
- **Paging:** PagerDuty pages only for escalations (≥ 30 min, long-running or blocked), keeps one incident per account and auto-resolves it.
- **Configurable:** thresholds, exclusions and channels live in a config table, so changes need no redeploy.
- **Native:** no external servers or functions. Webhook tokens are stored as Snowflake secrets.

See [`docs/DESIGN.md`](docs/DESIGN.md) for the architecture, flow, PagerDuty lifecycle and design decisions.

📊 **Architecture slides:** [`docs/architecture/Snowflake_Query_Alerts_Architecture.pptx`](docs/architecture/Snowflake_Query_Alerts_Architecture.pptx) ([PDF preview](docs/architecture/Snowflake_Query_Alerts_Architecture.pdf)) — 10 slides: alert types, solution architecture, processing flow, channels, PagerDuty lifecycle, code modules, security, design decisions, deploy and operate.

---

## Repository layout

```
├── README.md
├── docs/
│   ├── DESIGN.md                      architecture & design decisions
│   └── architecture/
│       ├── Snowflake_Query_Alerts_Architecture.pptx   architecture deck (10 slides)
│       ├── Snowflake_Query_Alerts_Architecture.pdf    PDF preview of the deck
│       └── build_architecture_deck.js                 pptxgenjs generator (regenerate the deck)
├── deploy/
│   └── deploy_all.sql                 SnowSQL runner (!source, in order)
└── sql/
    ├── 00_setup_role_database.sql     role, OBSERVABILITY.QUERY_ALERTS, privileges      (ACCOUNTADMIN)
    ├── 01_config_and_log_tables.sql   QM_CONFIG, QM_ALERT_LOG, QM_CHANNEL_STATE
    ├── 02_channel_email.sql           ┐
    ├── 03_channel_teams.sql           │ one module per channel:
    ├── 04_channel_slack.sql           │  A) secret + integration (ACCOUNTADMIN)
    ├── 05_channel_pagerduty.sql       ┘  B) sender procedure  C) enable switch
    ├── 06_procedure_scan.sql          SP_QM_SCAN — detect, dedupe, dispatch, log
    ├── 07_task_schedule.sql           TASK_QM_SCAN — every minute, serverless
    ├── 08_views.sql                   V_QM_OPEN_ALERTS, V_QM_ALERT_HISTORY, V_QM_MONITOR_HEALTH
    ├── 09_test_and_operate.sql        SP_QM_TEST_CHANNELS, end-to-end test, day-2 SQL
    ├── 10_guardrails_optional.sql     statement / queue / lock timeouts (prevention)
    └── 99_teardown.sql                remove everything
```

Every channel is **independent**. Deploy only the ones the client uses, for example e-mail and Teams only.

---

## Prerequisites

- A Snowflake user with **ACCOUNTADMIN**, for setup only.
- Recipients for the channels you deploy:

| Channel | What you need | Where the token goes |
|---|---|---|
| E-mail | Recipient addresses of Snowflake users who have **verified** their e-mail (a Teams or Slack channel e-mail address also works) | `ALLOWED_RECIPIENTS` in `02` and `EMAIL_RECIPIENTS` in `QM_CONFIG` |
| Microsoft Teams | In the channel: **⋯ → Workflows → "Post to a channel when a webhook request is received"**, then copy the URL | Workflow-id part → secret; the rest → `WEBHOOK_URL` (with `SNOWFLAKE_WEBHOOK_SECRET` placeholder, no `:443`) in `03` |
| Slack | Slack app with **Incoming Webhooks** for the admin channel. URL: `https://hooks.slack.com/services/<TEAM_ID>/<WEBHOOK_ID>/<TOKEN>` | `<TEAM_ID>/<WEBHOOK_ID>/<TOKEN>` → secret in `04` |
| PagerDuty | Service → Integrations → **Events API V2**, then copy the **Integration Key** | Routing key → secret in `05` |

## Quick start

1. **Edit placeholders.** Search the `sql/` folder for `<<< replace`: recipients, the Teams URL and secret, the Slack secret and the PagerDuty routing key.
2. **Deploy.** Run in order, either with SnowSQL from the repo root:

   ```bash
   snowsql -a <account> -u <admin_user> -f deploy/deploy_all.sql
   ```

   or with the Snowflake CLI, one file at a time:

   ```bash
   for f in sql/00_*.sql sql/01_*.sql sql/02_*.sql sql/03_*.sql sql/04_*.sql sql/05_*.sql \
            sql/06_*.sql sql/08_*.sql sql/09_*.sql sql/07_*.sql; do snow sql -f "$f"; done
   ```

   You can also paste the files into a Snowsight worksheet in that order. Skip any channel module you don't need.
3. **Test the channels.** This sends a message marked TEST through every enabled channel; PagerDuty gets a trigger followed by a resolve.

   ```sql
   CALL OBSERVABILITY.QUERY_ALERTS.SP_QM_TEST_CHANNELS();
   -- e.g. EMAIL:OK TEAMS:OK SLACK:OK PAGERDUTY:TRIGGERED PAGERDUTY:RESOLVED
   ```

4. **Test end to end** with real long-running and lock-blocked queries; see section B of `09_test_and_operate.sql`.
5. **Start the schedule.** `07_task_schedule.sql` resumes `TASK_QM_SCAN`; `deploy_all.sql` runs it last.

## Configuration

All settings are rows in `OBSERVABILITY.QUERY_ALERTS.QM_CONFIG` and take effect on the next run:

```sql
UPDATE OBSERVABILITY.QUERY_ALERTS.QM_CONFIG SET PARAM_VALUE = '20'           WHERE PARAM_NAME = 'LONG_RUNNING_MIN';
UPDATE OBSERVABILITY.QUERY_ALERTS.QM_CONFIG SET PARAM_VALUE = 'ETL_WH'       WHERE PARAM_NAME = 'EXCLUDED_WAREHOUSES';
UPDATE OBSERVABILITY.QUERY_ALERTS.QM_CONFIG SET PARAM_VALUE = 'SVC_DBT'      WHERE PARAM_NAME = 'EXCLUDED_USERS';
UPDATE OBSERVABILITY.QUERY_ALERTS.QM_CONFIG SET PARAM_VALUE = 'FALSE'        WHERE PARAM_NAME = 'SLACK_ENABLED';
UPDATE OBSERVABILITY.QUERY_ALERTS.QM_CONFIG SET PARAM_VALUE = '60'           WHERE PARAM_NAME = 'PAGERDUTY_MIN_MINUTES';
```

| Parameter | Default | Meaning |
|---|---|---|
| `LONG_RUNNING_MIN` / `QUEUED_MIN` / `BLOCKED_MIN` | 15 / 5 / 5 | Thresholds (minutes) |
| `RENOTIFY_MIN` | 30 | Repeat interval while a query stays open |
| `EXCLUDED_WAREHOUSES` / `EXCLUDED_USERS` | empty | Comma lists to ignore |
| `INCLUDE_QUERY_TEXT` | FALSE | Include the first 150 characters of SQL in messages |
| `LOCK_DETAILS` | TRUE | Identify the lock holder (needs ACCOUNTADMIN, otherwise skipped) |
| `MAX_ROWS_IN_MESSAGE` | 25 | Digest size cap |
| `<CHANNEL>_ENABLED` | set by each channel script | Channel on/off: `EMAIL`, `TEAMS`, `SLACK`, `PAGERDUTY` |
| `EMAIL_RECIPIENTS` | — | Comma list of addresses |
| `PAGERDUTY_ALERT_TYPES` | LONG_RUNNING,BLOCKED | Alert types that page on-call |
| `PAGERDUTY_MIN_MINUTES` | 30 | Escalation threshold for paging |
| `PAGERDUTY_AUTO_RESOLVE` | TRUE | Resolve the incident when nothing page-eligible remains |

## Operating it

```sql
SELECT * FROM OBSERVABILITY.QUERY_ALERTS.V_QM_OPEN_ALERTS;                -- what is breaching now (+ CANCEL_SQL)
SELECT * FROM OBSERVABILITY.QUERY_ALERTS.V_QM_ALERT_HISTORY ORDER BY ALERT_DATE DESC;
SELECT * FROM OBSERVABILITY.QUERY_ALERTS.V_QM_MONITOR_HEALTH ORDER BY SCHEDULED_TIME DESC LIMIT 20;

SELECT SYSTEM$CANCEL_QUERY('<query_id>');              -- stop a runaway query
SHOW LOCKS IN ACCOUNT;                                  -- (ACCOUNTADMIN) inspect locks
SELECT SYSTEM$ABORT_TRANSACTION(<txn_id>);              -- release a blocking transaction

ALTER TASK OBSERVABILITY.QUERY_ALERTS.TASK_QM_SCAN SUSPEND;   -- pause
ALTER TASK OBSERVABILITY.QUERY_ALERTS.TASK_QM_SCAN RESUME;    -- resume
```

**Runbook additions**
- When a **new warehouse** is created, re-run the `MONITOR` grant block in `00_setup_role_database.sql`. Without it, queries on that warehouse aren't seen.
- The task **auto-suspends after 10 consecutive failures**. Check `V_QM_MONITOR_HEALTH` weekly.

## Troubleshooting

| Symptom | Check |
|---|---|
| Nothing detected | `V_QM_MONITOR_HEALTH`: is the task running? Does the role have `MONITOR` on the warehouse? Is the warehouse or user excluded? |
| `EMAIL:FAILED` | Recipient not a verified Snowflake user e-mail, or missing from `ALLOWED_RECIPIENTS` |
| `TEAMS:FAILED` / `SLACK:FAILED` | Secret value or URL format (no `:443`; placeholder in the right place). Run `SP_QM_TEST_CHANNELS()`. If the Teams workflow URL has `?api-version…&sig=…` query parameters, validate the format with Snowflake support and use the channel's e-mail address meanwhile. |
| `PAGERDUTY:FAILED` | Routing key, or the service isn't an Events API v2 integration |
| Blocked alert without holder | Expected unless the task runs as ACCOUNTADMIN (`SHOW LOCKS IN ACCOUNT`). Run it manually from the alert. |
| Too many alerts | Raise thresholds, add exclusions, or increase `RENOTIFY_MIN` |
| Last channel status per alert | `QM_ALERT_LOG.LAST_CHANNEL_STATUS`, and the task `RETURN_VALUE` in `V_QM_MONITOR_HEALTH` |

## Prevention (optional)

`sql/10_guardrails_optional.sql` contains example settings so Snowflake acts on its own:
- `STATEMENT_TIMEOUT_IN_SECONDS` to stop runaway queries;
- `STATEMENT_QUEUED_TIMEOUT_IN_SECONDS` to cap time in the queue;
- `LOCK_TIMEOUT` to cap lock waits;
- multi-cluster warehouses to reduce queueing.

## Uninstall

```sql
-- sql/99_teardown.sql (ACCOUNTADMIN): drops the QUERY_ALERTS schema, integrations and role; keeps the OBSERVABILITY database
```

## References

- [Webhook notifications: Slack, Teams, PagerDuty](https://docs.snowflake.com/en/user-guide/notifications/webhook-notifications)
- [QUERY_HISTORY table functions](https://docs.snowflake.com/en/sql-reference/functions/query_history)
- [SHOW LOCKS](https://docs.snowflake.com/en/sql-reference/sql/show-locks)
- [SYSTEM$SEND_SNOWFLAKE_NOTIFICATION](https://docs.snowflake.com/en/sql-reference/stored-procedures/system_send_snowflake_notification)
