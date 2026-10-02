# Changelog

## 2.0.0 — 2026-10-02
- Added **Slack** channel (`sql/04_channel_slack.sql`): incoming webhook, mrkdwn digest.
- Added **PagerDuty** channel (`sql/05_channel_pagerduty.sql`): Events API v2 trigger and auto-resolve, escalation threshold, one incident per account.
- Split the single script into **separate sections**: foundation, one module per channel, engine, schedule, views, test/operate, guardrails, teardown.
- Channel contract: each channel has its own sender procedure `SP_QM_SEND_<CHANNEL>` and enable switch; the engine dispatches only to enabled channels, and channel failures are isolated.
- Added `QM_CHANNEL_STATE`, `PAGERDUTY_TRIGGERED_AT` in `QM_ALERT_LOG`, `V_QM_MONITOR_HEALTH`, `SP_QM_TEST_CHANNELS`, `99_teardown.sql`, `deploy/deploy_all.sql`.

## 1.0.0 — 2026-10-02
- Initial design: long-running (≥ 15 min), queued (≥ 5 min) and lock-blocked (≥ 5 min) query alerts to E-mail and Microsoft Teams in `OBSERVABILITY.QUERY_ALERTS`.
