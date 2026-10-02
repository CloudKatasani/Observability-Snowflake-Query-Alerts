/*
 * Builds docs/architecture/Snowflake_Query_Alerts_Architecture.pptx
 *   node docs/architecture/build_architecture_deck.js
 * Requires: pptxgenjs, react, react-dom, react-icons, sharp
 * (optional) APPLY_THEME=/path/to/apply_theme.js to write theme colors into the deck.
 */
const path = require("path");
const pptxgen = require("pptxgenjs");
const React = require("react");
const ReactDOMServer = require("react-dom/server");
const sharp = require("sharp");
const fa = require("react-icons/fa");
const si = require("react-icons/si");
const md = require("react-icons/md");

const OUT = path.join(__dirname, "Snowflake_Query_Alerts_Architecture.pptx");

// Capgemini palette
const HEX = {
  navy: "12446E", blue: "0070AD", deep: "003D5A", sky: "12ABDB", skyLight: "A4DBE8",
  skyTint: "E8F4FB", coral: "E94B89", coralBg: "FCE4EE", ink: "1F2A36", grey: "5B6B7B", white: "FFFFFF",
};
const THEME = {
  name: "Capgemini Observability",
  headFontFace: "Cambria",
  bodyFontFace: "Calibri",
  colors: {
    dk1: HEX.ink, lt1: HEX.white, dk2: HEX.navy, lt2: HEX.skyTint,
    accent1: HEX.blue, accent2: HEX.sky, accent3: HEX.coral, accent4: HEX.deep,
    accent5: HEX.skyLight, accent6: HEX.coralBg, hlink: HEX.blue, folHlink: HEX.deep,
  },
};

async function icon(Comp, hex, size = 256) {
  const svg = ReactDOMServer.renderToStaticMarkup(React.createElement(Comp, { color: "#" + hex, size: String(size) }));
  const png = await sharp(Buffer.from(svg)).png().toBuffer();
  return "image/png;base64," + png.toString("base64");
}

(async () => {
  const pres = new pptxgen();
  pres.layout = "LAYOUT_WIDE"; // 13.333 x 7.5
  pres.title = "Snowflake Real-Time Query Alerts - Architecture";
  pres.author = "Capgemini - Data and AI Architecture";
  pres.company = "Capgemini";
  pres.theme = { headFontFace: THEME.headFontFace, bodyFontFace: THEME.bodyFontFace };
  const C = pres.SchemeColor;
  const S = pres.shapes;

  // ---------- layouts ----------
  pres.defineSlideMaster({
    title: "TITLE_DARK",
    background: { color: C.text2 },
    objects: [
      { placeholder: { options: { name: "title", type: "title", x: 0.8, y: 2.3, w: 11.7, h: 1.4, fontFace: "Cambria", fontSize: 40, bold: true, color: C.background1, valign: "bottom", margin: 0 }, text: "" } },
      { placeholder: { options: { name: "body", type: "body", x: 0.8, y: 3.9, w: 11.7, h: 1.2, fontFace: "Calibri", fontSize: 20, color: C.accent5, valign: "top", margin: 0 }, text: "" } },
      { text: { text: "Capgemini  |  Platform Observability", options: { x: 0.8, y: 6.7, w: 8, h: 0.35, fontFace: "Calibri", fontSize: 11, color: C.accent5, margin: 0 } } },
    ],
  });
  pres.defineSlideMaster({
    title: "CONTENT",
    background: { color: C.background1 },
    margin: [0.5, 0.6, 0.6, 0.6],
    objects: [
      { placeholder: { options: { name: "title", type: "title", x: 0.6, y: 0.35, w: 12.1, h: 0.8, fontFace: "Cambria", fontSize: 30, bold: true, color: C.text2, valign: "middle", margin: 0 }, text: "" } },
      { text: { text: "Snowflake Real-Time Query Alerts  |  Architecture  |  OBSERVABILITY.QUERY_ALERTS", options: { x: 0.6, y: 7.05, w: 9, h: 0.3, fontFace: "Calibri", fontSize: 9, color: C.text1, margin: 0 } } },
    ],
    slideNumber: { x: 12.2, y: 7.05, w: 0.5, h: 0.3, fontFace: "Calibri", fontSize: 9, color: C.text2, align: "right" },
  });

  // ---------- icons ----------
  const I = {
    clock: await icon(fa.FaStopwatch, HEX.white), hourglass: await icon(fa.FaHourglassHalf, HEX.white),
    lock: await icon(fa.FaLock, HEX.white), mail: await icon(fa.FaEnvelope, HEX.white),
    teams: await icon(md.MdGroups, HEX.white), slack: await icon(si.SiSlack, HEX.white),
    pd: await icon(si.SiPagerduty, HEX.white), snow: await icon(si.SiSnowflake, HEX.sky),
    cogs: await icon(fa.FaCogs, HEX.white), db: await icon(fa.FaDatabase, HEX.white),
    shield: await icon(fa.FaShieldAlt, HEX.white), eye: await icon(fa.FaEye, HEX.white),
    rocket: await icon(fa.FaRocket, HEX.white), bell: await icon(fa.FaBell, HEX.white),
  };
  const iconCircle = (slide, img, x, y, d, fill, name) => {
    slide.addShape(S.OVAL, { x, y, w: d, h: d, fill: { color: fill }, line: { color: fill }, objectName: name + " circle" });
    const p = d * 0.22;
    slide.addImage({ data: img, x: x + p, y: y + p, w: d - 2 * p, h: d - 2 * p, objectName: name + " icon" });
  };
  const arrow = (slide, x1, y1, x2, y2, color = C.accent1, name = "arrow") => {
    const flipH = x2 < x1, flipV = y2 < y1;
    slide.addShape(S.LINE, {
      x: Math.min(x1, x2), y: Math.min(y1, y2), w: Math.max(Math.abs(x2 - x1), 0.001), h: Math.max(Math.abs(y2 - y1), 0.001),
      flipH, flipV, line: { color, width: 1.75, endArrowType: "triangle" }, objectName: name,
    });
  };
  const box = (slide, x, y, w, h, fill, lineColor, name, rect = S.ROUNDED_RECTANGLE) =>
    slide.addShape(rect, { x, y, w, h, fill: { color: fill }, line: { color: lineColor, width: 1 }, rectRadius: rect === S.ROUNDED_RECTANGLE ? 0.08 : undefined, objectName: name });

  // ============ 1. Title ============
  pres.addSection({ title: "Overview" });
  let s = pres.addSlide({ masterName: "TITLE_DARK", sectionTitle: "Overview" });
  s.addText("Snowflake Real-Time Query Alerts", { placeholder: "title" });
  s.addText("Architecture  ·  long-running, queued and lock-blocked queries  ·  E-mail, Microsoft Teams, Slack, PagerDuty", { placeholder: "body" });
  s.addImage({ data: I.snow, x: 0.8, y: 1.2, w: 0.8, h: 0.8, objectName: "snowflake mark" });
  s.addText("v2.0  ·  OBSERVABILITY.QUERY_ALERTS  ·  October 2026", { x: 0.8, y: 5.4, w: 8, h: 0.4, fontSize: 14, color: C.background1, margin: 0, isTextBox: true });
  s.addNotes("Architecture of the native Snowflake alerting solution for long-running, queued and lock-blocked queries, with four notification channels.");

  // ============ 2. What we detect ============
  s = pres.addSlide({ masterName: "CONTENT", sectionTitle: "Overview" });
  s.addText("What the Admin team is alerted on", { placeholder: "title" });
  const cards = [
    { img: I.clock, fill: C.accent1, big: "15 min", t: "LONG_RUNNING", d: "Query executing 15 min or more. Time spent queued or waiting on a lock is excluded.", st: "Status RUNNING" },
    { img: I.hourglass, fill: C.accent2, big: "5 min", t: "QUEUED", d: "Query waiting for warehouse capacity or a warehouse resume for 5 min or more.", st: "Status QUEUED, RESUMING_WAREHOUSE" },
    { img: I.lock, fill: C.accent3, big: "5 min", t: "BLOCKED", d: "Query waiting on a table lock for 5 min or more. Names the locked table and the blocking query.", st: "Status BLOCKED" },
  ];
  cards.forEach((c, i) => {
    const x = 0.6 + i * 4.1;
    box(s, x, 1.45, 3.8, 4.1, C.background2, C.background2, "card " + c.t);
    iconCircle(s, c.img, x + 0.35, 1.75, 0.9, c.fill, c.t);
    s.addText(c.big, { x: x + 1.45, y: 1.7, w: 2.2, h: 1.0, fontFace: "Cambria", fontSize: 44, bold: true, color: C.text2, margin: 0, valign: "middle", isTextBox: true });
    s.addText(c.t, { x: x + 0.35, y: 2.95, w: 3.2, h: 0.45, fontSize: 18, bold: true, color: C.text2, margin: 0, isTextBox: true });
    s.addText(c.d, { x: x + 0.35, y: 3.45, w: 3.2, h: 1.3, fontSize: 14, color: C.text1, margin: 0, valign: "top", isTextBox: true });
    s.addText(c.st, { x: x + 0.35, y: 4.85, w: 3.2, h: 0.45, fontFace: "Courier New", fontSize: 11, color: C.accent4, margin: 0, isTextBox: true });
  });
  const kpis = [["about 1 min", "detection delay"], ["4", "notification channels"], ["0", "external servers"], ["30 min", "re-notify window"]];
  kpis.forEach((k, i) => {
    const x = 0.6 + i * 3.075;
    s.addText(k[0], { x, y: 5.8, w: 2.9, h: 0.6, fontFace: "Cambria", fontSize: 26, bold: true, color: C.accent1, margin: 0, isTextBox: true });
    s.addText(k[1], { x, y: 6.4, w: 2.9, h: 0.35, fontSize: 12, color: C.text1, margin: 0, isTextBox: true });
  });
  s.addNotes("Thresholds are defaults held in QM_CONFIG and can be changed without redeploying.");

  // ============ 3. Solution architecture ============
  pres.addSection({ title: "Architecture" });
  s = pres.addSlide({ masterName: "CONTENT", sectionTitle: "Architecture" });
  s.addText("Solution architecture", { placeholder: "title" });
  // Snowflake boundary
  box(s, 0.5, 1.3, 9.35, 5.55, C.background2, C.accent5, "Snowflake account boundary");
  s.addText("Snowflake account  ·  OBSERVABILITY.QUERY_ALERTS", { x: 0.7, y: 1.38, w: 6, h: 0.3, fontSize: 11, bold: true, color: C.accent4, margin: 0, isTextBox: true });
  // task
  box(s, 0.75, 1.85, 2.35, 0.95, C.text2, C.text2, "task");
  s.addText([{ text: "TASK_QM_SCAN", options: { bold: true, breakLine: true } }, { text: "serverless · every 1 min", options: { fontSize: 11 } }],
    { x: 0.75, y: 1.85, w: 2.35, h: 0.95, fontSize: 13, color: C.background1, align: "center", valign: "middle", margin: 0.05, isTextBox: true });
  // sources
  box(s, 0.75, 3.15, 2.35, 1.05, C.background1, C.accent1, "query history source");
  s.addText([{ text: "QUERY_HISTORY_BY_WAREHOUSE()", options: { bold: true, breakLine: true, fontSize: 10 } }, { text: "real-time, per warehouse", options: { fontSize: 11 } }],
    { x: 0.75, y: 3.15, w: 2.35, h: 1.05, fontSize: 11, color: C.text2, align: "center", valign: "middle", margin: 0.05, isTextBox: true });
  box(s, 0.75, 4.5, 2.35, 0.95, C.background1, C.accent3, "locks source");
  s.addText([{ text: "SHOW LOCKS IN ACCOUNT", options: { bold: true, breakLine: true, fontSize: 10 } }, { text: "lock holder (best effort)", options: { fontSize: 11 } }],
    { x: 0.75, y: 4.5, w: 2.35, h: 0.95, fontSize: 11, color: C.text2, align: "center", valign: "middle", margin: 0.05, isTextBox: true });
  // engine
  box(s, 3.6, 1.85, 2.9, 2.35, C.accent1, C.accent1, "engine");
  iconCircle(s, I.cogs, 4.75, 2.0, 0.6, C.accent4, "engine");
  s.addText([{ text: "SP_QM_SCAN", options: { bold: true, fontSize: 16, breakLine: true } }, { text: "detect · classify · dedupe · dispatch · log", options: { fontSize: 11 } }],
    { x: 3.7, y: 2.7, w: 2.7, h: 1.3, color: C.background1, align: "center", valign: "middle", margin: 0, isTextBox: true });
  arrow(s, 3.1, 2.32, 3.6, 2.32, C.text2, "task to engine");
  arrow(s, 3.1, 3.67, 3.6, 3.4, C.accent1, "history to engine");
  arrow(s, 3.1, 4.97, 3.6, 3.9, C.accent3, "locks to engine");
  // tables
  const tbls = [["QM_CONFIG", "thresholds · switches"], ["QM_ALERT_LOG", "dedupe · audit"], ["QM_CHANNEL_STATE", "PagerDuty state"]];
  tbls.forEach((t, i) => {
    const y = 4.5 + i * 0.33;
    s.addShape(S.ROUNDED_RECTANGLE, { x: 3.6, y, w: 2.9, h: 0.29, fill: { color: C.accent5 }, line: { color: C.accent5 }, rectRadius: 0.05, objectName: "table " + t[0] });
    s.addText([{ text: t[0], options: { bold: true, fontFace: "Courier New" } }, { text: "   " + t[1] }],
      { x: 3.7, y, w: 2.75, h: 0.29, fontSize: 9.5, color: C.accent4, valign: "middle", margin: 0, isTextBox: true });
  });
  arrow(s, 5.05, 4.2, 5.05, 4.5, C.accent4, "engine to tables");
  // views
  box(s, 0.75, 5.75, 5.75, 0.85, C.background1, C.accent4, "views");
  iconCircle(s, I.eye, 0.9, 5.88, 0.6, C.accent4, "views");
  s.addText([{ text: "Admin views  ", options: { bold: true } }, { text: "V_QM_OPEN_ALERTS · V_QM_ALERT_HISTORY · V_QM_MONITOR_HEALTH" }],
    { x: 1.6, y: 5.75, w: 4.85, h: 0.85, fontSize: 11, color: C.text2, valign: "middle", margin: 0, isTextBox: true });
  arrow(s, 5.05, 5.45, 5.05, 5.75, C.accent4, "tables to views");
  // senders + endpoints
  const ch = [
    { n: "SP_QM_SEND_EMAIL", i: "QM_EMAIL_INT", e: "Admin mailbox", sub: "HTML digest", img: I.mail, fill: C.accent4 },
    { n: "SP_QM_SEND_TEAMS", i: "QM_TEAMS_INT", e: "Microsoft Teams", sub: "Workflows webhook", img: I.teams, fill: C.accent1 },
    { n: "SP_QM_SEND_SLACK", i: "QM_SLACK_INT", e: "Slack", sub: "incoming webhook", img: I.slack, fill: C.accent2 },
    { n: "SP_QM_SEND_PAGERDUTY", i: "TRIGGER / RESOLVE ints", e: "PagerDuty", sub: "Events API v2 incident", img: I.pd, fill: C.accent3 },
  ];
  ch.forEach((c, i) => {
    const y = 1.85 + i * 1.2;
    box(s, 7.0, y, 2.6, 0.95, C.background1, c.fill, "sender " + c.n);
    s.addText([{ text: c.n, options: { bold: true, breakLine: true, fontSize: 10.5 } }, { text: c.i, options: { fontSize: 10, color: C.text1 } }],
      { x: 7.0, y, w: 2.6, h: 0.95, color: C.text2, align: "center", valign: "middle", margin: 0.05, isTextBox: true });
    arrow(s, 6.5, 3.02, 7.0, y + 0.47, C.accent1, "engine to " + c.n);
    arrow(s, 9.6, y + 0.47, 10.15, y + 0.47, c.fill, c.n + " out");
    iconCircle(s, c.img, 10.2, y + 0.12, 0.72, c.fill, c.e);
    s.addText([{ text: c.e, options: { bold: true, breakLine: true } }, { text: c.sub, options: { fontSize: 11, color: C.text1 } }],
      { x: 11.05, y, w: 1.75, h: 0.95, fontSize: 13, color: C.text2, valign: "middle", margin: 0, isTextBox: true });
  });
  s.addText("External channels", { x: 10.2, y: 1.38, w: 2.6, h: 0.3, fontSize: 11, bold: true, color: C.accent4, margin: 0, isTextBox: true });
  s.addText("Channels run independently; one failing never blocks the others. Tokens are stored as Snowflake secrets.",
    { x: 10.2, y: 6.35, w: 2.7, h: 0.55, fontSize: 9, italic: true, color: C.text1, valign: "top", margin: 0, isTextBox: true });
  s.addNotes("Everything inside the boundary is native Snowflake: serverless task, SQL stored procedures, tables, views, secrets and notification integrations.");

  // ============ 4. Processing flow ============
  s = pres.addSlide({ masterName: "CONTENT", sectionTitle: "Architecture" });
  s.addText("Processing flow, every minute", { placeholder: "title" });
  const steps = [
    ["Read config", "Thresholds, exclusions and channel switches from QM_CONFIG"],
    ["Collect", "In-flight queries per warehouse from real-time query history"],
    ["Measure", "Executing minutes for RUNNING; wait minutes for QUEUED and BLOCKED"],
    ["Lock holder", "SHOW LOCKS joins WAITING to HOLDING on the same table"],
    ["Decide", "New, or open past 30 min; PagerDuty only for escalations"],
    ["Dispatch", "Digest to e-mail, Teams, Slack; trigger or resolve PagerDuty"],
    ["Log", "Upsert QM_ALERT_LOG; resolve alerts that cleared"],
  ];
  steps.forEach((st, i) => {
    const x = 0.6 + i * 1.75;
    box(s, x, 2.0, 1.6, 2.95, i % 2 ? C.background2 : C.background1, C.accent5, "step " + (i + 1));
    s.addShape(S.OVAL, { x: x + 0.5, y: 1.55, w: 0.6, h: 0.6, fill: { color: C.accent1 }, line: { color: C.background1, width: 2 }, objectName: "badge " + (i + 1) });
    s.addText(String(i + 1), { x: x + 0.5, y: 1.55, w: 0.6, h: 0.6, fontSize: 18, bold: true, color: C.background1, align: "center", valign: "middle", margin: 0, isTextBox: true });
    s.addText(st[0], { x: x + 0.1, y: 2.35, w: 1.4, h: 0.5, fontSize: 15, bold: true, color: C.text2, align: "center", margin: 0, isTextBox: true });
    s.addText(st[1], { x: x + 0.12, y: 2.9, w: 1.36, h: 1.95, fontSize: 13, color: C.text1, valign: "top", margin: 0, isTextBox: true });
    if (i < steps.length - 1) arrow(s, x + 1.6, 3.45, x + 1.75, 3.45, C.accent1, "flow " + (i + 1));
  });
  box(s, 0.6, 5.35, 12.1, 1.3, C.background2, C.background2, "rules panel");
  s.addText([
    { text: "Executing minutes  ", options: { bold: true, color: C.text2 } },
    { text: "elapsed since start minus queued, provisioning, repair and lock time.     ", options: {} },
    { text: "Re-notify  ", options: { bold: true, color: C.text2 } },
    { text: "the same query and alert type is repeated at most every 30 min while it stays open.     ", options: {} },
    { text: "Isolation  ", options: { bold: true, color: C.text2 } },
    { text: "each channel call has its own error handler.", options: {} },
  ], { x: 0.85, y: 5.35, w: 11.6, h: 1.3, fontSize: 13, color: C.text1, valign: "middle", margin: 0, isTextBox: true });
  s.addNotes("SP_QM_SCAN performs these seven steps on every run of TASK_QM_SCAN.");

  // ============ 5. Channels ============
  pres.addSection({ title: "Channels" });
  s = pres.addSlide({ masterName: "CONTENT", sectionTitle: "Channels" });
  s.addText("Notification channels", { placeholder: "title" });
  const chans = [
    { t: "E-mail", img: I.mail, fill: C.accent4, rows: [["Purpose", "Admin list, audit trail"], ["Format", "HTML table with action SQL"], ["Volume", "1 digest per run, max 25 rows"], ["Setup", "Verified Snowflake user e-mails"]] },
    { t: "Microsoft Teams", img: I.teams, fill: C.accent1, rows: [["Purpose", "Admin channel awareness"], ["Format", "Adaptive Card list"], ["Volume", "Same digest as e-mail"], ["Setup", "Workflows webhook URL, id as secret"]] },
    { t: "Slack", img: I.slack, fill: C.accent2, rows: [["Purpose", "Admin channel, if Slack is used"], ["Format", "mrkdwn bullet list"], ["Volume", "Same digest as e-mail"], ["Setup", "Incoming webhook, path as secret"]] },
    { t: "PagerDuty", img: I.pd, fill: C.accent3, rows: [["Purpose", "On-call escalation only"], ["Format", "Events API v2, severity error"], ["Volume", "1 incident per account, auto-resolve"], ["Setup", "Events v2 routing key as secret"]] },
  ];
  chans.forEach((c, i) => {
    const x = 0.6 + i * 3.075;
    box(s, x, 1.45, 2.9, 5.35, C.background2, C.background2, "channel card " + c.t);
    iconCircle(s, c.img, x + 0.25, 1.65, 0.75, c.fill, c.t);
    s.addText(c.t, { x: x + 1.1, y: 1.65, w: 1.75, h: 0.75, fontSize: 17, bold: true, color: C.text2, valign: "middle", margin: 0, isTextBox: true });
    c.rows.forEach((r, j) => {
      const y = 2.65 + j * 1.0;
      s.addText(r[0].toUpperCase(), { x: x + 0.25, y, w: 2.45, h: 0.3, fontSize: 10, bold: true, color: C.accent1, charSpacing: 1, margin: 0, isTextBox: true });
      s.addText(r[1], { x: x + 0.25, y: y + 0.3, w: 2.45, h: 0.6, fontSize: 13, color: C.text1, valign: "top", margin: 0, isTextBox: true });
    });
  });
  s.addNotes("Every channel is a separate module (sql/02 to 05) with its own sender procedure and enable switch in QM_CONFIG.");

  // ============ 6. PagerDuty lifecycle ============
  s = pres.addSlide({ masterName: "CONTENT", sectionTitle: "Channels" });
  s.addText("PagerDuty: escalation and auto-resolve", { placeholder: "title" });
  box(s, 0.9, 2.4, 2.6, 1.4, C.background2, C.accent4, "state closed");
  s.addText([{ text: "CLOSED", options: { bold: true, fontSize: 22, breakLine: true } }, { text: "no open incident", options: { fontSize: 12 } }],
    { x: 0.9, y: 2.4, w: 2.6, h: 1.4, color: C.text2, align: "center", valign: "middle", margin: 0, isTextBox: true });
  box(s, 5.6, 2.4, 2.6, 1.4, C.accent3, C.accent3, "state open");
  s.addText([{ text: "OPEN", options: { bold: true, fontSize: 22, breakLine: true } }, { text: "one incident per account", options: { fontSize: 12 } }],
    { x: 5.6, y: 2.4, w: 2.6, h: 1.4, color: C.background1, align: "center", valign: "middle", margin: 0, isTextBox: true });
  arrow(s, 3.5, 2.7, 5.6, 2.7, C.accent3, "trigger arrow");
  s.addText("trigger: page-eligible query found", { x: 3.55, y: 2.25, w: 2.0, h: 0.4, fontSize: 11, color: C.text1, align: "center", margin: 0, isTextBox: true });
  arrow(s, 5.6, 3.5, 3.5, 3.5, C.accent4, "resolve arrow");
  s.addText("resolve: nothing eligible left", { x: 3.55, y: 3.55, w: 2.0, h: 0.4, fontSize: 11, color: C.text1, align: "center", margin: 0, isTextBox: true });
  s.addText("↻  still eligible after 30 min: trigger again (updates the same incident)", { x: 5.3, y: 3.95, w: 3.2, h: 0.6, fontSize: 11, italic: true, color: C.text1, align: "center", margin: 0, isTextBox: true });
  box(s, 0.9, 4.9, 7.3, 1.75, C.background2, C.background2, "template note");
  s.addText([
    { text: "Two integrations, one secret.  ", options: { bold: true, color: C.text2 } },
    { text: "Snowflake webhook templates are static, so QM_PAGERDUTY_TRIGGER_INT and QM_PAGERDUTY_RESOLVE_INT share the routing key and a fixed dedup_key. Incident state is tracked in QM_CHANNEL_STATE. Give each Snowflake account its own dedup_key.", options: {} },
  ], { x: 1.15, y: 4.9, w: 6.8, h: 1.75, fontSize: 13, color: C.text1, valign: "middle", margin: 0, isTextBox: true });
  // policy panel
  box(s, 8.8, 1.45, 3.9, 5.2, C.text2, C.text2, "policy panel");
  s.addText("Paging policy", { x: 9.1, y: 1.65, w: 3.4, h: 0.5, fontSize: 18, bold: true, color: C.background1, margin: 0, isTextBox: true });
  const pol = [["Types", "LONG_RUNNING, BLOCKED"], ["Escalation", "query at 30 min or more"], ["Re-trigger", "every 30 min while eligible"], ["Severity", "error"], ["Auto-resolve", "on, configurable"]];
  pol.forEach((p, i) => {
    const y = 2.35 + i * 0.82;
    s.addText(p[0].toUpperCase(), { x: 9.1, y, w: 3.4, h: 0.3, fontSize: 10, bold: true, color: C.accent5, charSpacing: 1, margin: 0, isTextBox: true });
    s.addText(p[1], { x: 9.1, y: y + 0.3, w: 3.4, h: 0.4, fontSize: 14, color: C.background1, margin: 0, isTextBox: true });
  });
  s.addNotes("QUEUED alerts go to chat and e-mail only. PAGERDUTY_ALERT_TYPES, PAGERDUTY_MIN_MINUTES and PAGERDUTY_AUTO_RESOLVE are in QM_CONFIG.");

  // ============ 7. Code modules ============
  pres.addSection({ title: "Build and run" });
  s = pres.addSlide({ masterName: "CONTENT", sectionTitle: "Build and run" });
  s.addText("Modular code: one script per concern", { placeholder: "title" });
  const mods = [
    ["00", "Setup role and database", "Foundation", C.accent4], ["01", "Config and log tables", "Foundation", C.accent4],
    ["02", "Channel: e-mail", "Channel", C.accent1], ["03", "Channel: Teams", "Channel", C.accent1],
    ["04", "Channel: Slack", "Channel", C.accent1], ["05", "Channel: PagerDuty", "Channel", C.accent1],
    ["06", "Engine SP_QM_SCAN", "Engine", C.accent3], ["07", "Task schedule", "Schedule", C.accent3],
    ["08", "Admin views", "Consumption", C.accent2], ["09", "Test and operate", "Operate", C.accent2],
    ["10", "Guardrails, optional", "Prevention", C.text1], ["99", "Teardown", "Remove", C.text1],
  ];
  mods.forEach((m, i) => {
    const col = i % 3, row = Math.floor(i / 3);
    const x = 0.6 + col * 2.6, y = 1.45 + row * 1.33;
    box(s, x, y, 2.45, 1.18, C.background2, C.background2, "module " + m[0]);
    s.addShape(S.ROUNDED_RECTANGLE, { x: x + 0.15, y: y + 0.18, w: 0.62, h: 0.42, fill: { color: m[3] }, line: { color: m[3] }, rectRadius: 0.06, objectName: "badge " + m[0] });
    s.addText(m[0], { x: x + 0.15, y: y + 0.18, w: 0.62, h: 0.42, fontFace: "Courier New", fontSize: 14, bold: true, color: C.background1, align: "center", valign: "middle", margin: 0, isTextBox: true });
    s.addText(m[2].toUpperCase(), { x: x + 0.9, y: y + 0.2, w: 1.5, h: 0.38, fontSize: 9, bold: true, color: C.accent1, valign: "middle", margin: 0, isTextBox: true });
    s.addText(m[1], { x: x + 0.15, y: y + 0.68, w: 2.2, h: 0.42, fontSize: 13, bold: true, color: C.text2, valign: "middle", margin: 0, isTextBox: true });
  });
  box(s, 8.6, 1.45, 4.1, 5.17, C.text2, C.text2, "contract panel");
  s.addText("Channel contract", { x: 8.9, y: 1.65, w: 3.5, h: 0.5, fontSize: 18, bold: true, color: C.background1, margin: 0, isTextBox: true });
  const con = [["A", "Secret and notification integration", "ACCOUNTADMIN"], ["B", "Sender SP_QM_SEND_{CHANNEL}", "formats session temp table QM_CANDIDATES"], ["C", "Enable switch", "{CHANNEL}_ENABLED = TRUE in QM_CONFIG"]];
  con.forEach((c, i) => {
    const y = 2.35 + i * 1.15;
    s.addShape(S.OVAL, { x: 8.9, y, w: 0.6, h: 0.6, fill: { color: C.accent2 }, line: { color: C.accent2 }, objectName: "contract " + c[0] });
    s.addText(c[0], { x: 8.9, y, w: 0.6, h: 0.6, fontSize: 18, bold: true, color: C.background1, align: "center", valign: "middle", margin: 0, isTextBox: true });
    s.addText([{ text: c[1], options: { bold: true, breakLine: true } }, { text: c[2], options: { fontSize: 11, color: C.accent5 } }],
      { x: 9.65, y: y - 0.1, w: 2.9, h: 0.85, fontSize: 13, color: C.background1, valign: "middle", margin: 0, isTextBox: true });
  });
  s.addText("Add Opsgenie, ServiceNow or Google Chat by copying a channel module and adding one IF block in SP_QM_SCAN.",
    { x: 8.9, y: 5.75, w: 3.6, h: 0.75, fontSize: 11, italic: true, color: C.accent5, margin: 0, isTextBox: true });
  s.addNotes("Deploy only the channel modules the client needs; the engine calls enabled channels only.");

  // ============ 8. Security ============
  s = pres.addSlide({ masterName: "CONTENT", sectionTitle: "Build and run" });
  s.addText("Security and privileges", { placeholder: "title" });
  const hdr = (t) => ({ text: t, options: { bold: true, color: C.background1, fill: { color: C.text2 }, fontSize: 13 } });
  const cell = (t, o = {}) => ({ text: t, options: Object.assign({ fontSize: 12, color: C.text1 }, o) });
  s.addTable([
    [hdr("Need"), hdr("Grant to OPS_QUERY_MONITOR"), hdr("Note")],
    [cell("See all users' queries in real time", { bold: true }), cell("MONITOR on every warehouse"), cell("Re-run the grant block when a warehouse is created")],
    [cell("Run the serverless task", { bold: true }), cell("EXECUTE TASK, EXECUTE MANAGED TASK"), cell("No warehouse to manage")],
    [cell("Send notifications", { bold: true }), cell("USAGE on integrations and secrets"), cell("Tokens never appear in code or logs")],
    [cell("Identify the lock holder", { bold: true }), cell("SHOW LOCKS IN ACCOUNT needs ACCOUNTADMIN"), cell("Without it, blocked queries still alert, no holder id")],
    [cell("Setup", { bold: true }), cell("ACCOUNTADMIN, once"), cell("Scripts 00 and 02 to 05, section A")],
  ], { x: 0.6, y: 1.45, w: 8.1, colW: [2.5, 2.9, 2.7], rowH: 0.62, border: { type: "solid", pt: 0.75, color: HEX.skyLight }, fill: { color: HEX.white }, valign: "middle", margin: 0.08 });
  box(s, 9.1, 1.45, 3.6, 5.2, C.background2, C.background2, "privacy panel");
  iconCircle(s, I.shield, 9.35, 1.7, 0.8, C.accent4, "privacy");
  s.addText("Privacy by default", { x: 10.3, y: 1.7, w: 2.3, h: 0.8, fontSize: 17, bold: true, color: C.text2, valign: "middle", margin: 0, isTextBox: true });
  s.addText([
    { text: "Query text excluded from messages (INCLUDE_QUERY_TEXT = FALSE)", options: { bullet: true, breakLine: true } },
    { text: "Webhook tokens stored as Snowflake secrets", options: { bullet: true, breakLine: true } },
    { text: "E-mail only to verified Snowflake users", options: { bullet: true, breakLine: true } },
    { text: "No IMPORTED PRIVILEGES on the SNOWFLAKE database", options: { bullet: true } },
  ], { x: 9.35, y: 2.75, w: 3.15, h: 3.6, fontSize: 13, color: C.text1, valign: "top", paraSpaceAfter: 8, margin: 0, isTextBox: true });
  s.addNotes("Least-privilege role OPS_QUERY_MONITOR owns all objects; ACCOUNTADMIN is required only during setup.");

  // ============ 9. Design decisions ============
  s = pres.addSlide({ masterName: "CONTENT", sectionTitle: "Build and run" });
  s.addText("Design decisions and limitations", { placeholder: "title" });
  s.addTable([
    [hdr("Topic"), hdr("Decision"), hdr("Why")],
    [cell("Real-time source", { bold: true }), cell("INFORMATION_SCHEMA query history"), cell("ACCOUNT_USAGE.QUERY_HISTORY lags up to about 45 min")],
    [cell("Polling", { bold: true }), cell("Serverless task every minute"), cell("No native event for a query passing N minutes")],
    [cell("Task, not alert object", { bold: true }), cell("Loop over warehouses, multi-channel dispatch"), cell("An alert condition must be a single query")],
    [cell("Per-warehouse scan", { bold: true }), cell("Up to 10,000 recent queries each"), cell("A busy warehouse cannot hide another's query")],
    [cell("Alert fatigue", { bold: true }), cell("Digest, 30 min re-notify, exclusions"), cell("PagerDuty only for escalations")],
    [cell("Cost", { bold: true }), cell("One XSMALL serverless run per minute"), cell("Typically seconds of compute; 2-minute schedule halves it")],
    [cell("Known limit", { bold: true }), cell("Warehouse-less queries not covered"), cell("Metadata-only statements rarely run long")],
  ], { x: 0.6, y: 1.45, w: 12.1, colW: [2.6, 4.5, 5.0], rowH: 0.6, border: { type: "solid", pt: 0.75, color: HEX.skyLight }, fill: { color: HEX.white }, valign: "middle", margin: 0.08 });
  s.addNotes("Full rationale in docs/DESIGN.md section 6.");

  // ============ 10. Deploy and operate ============
  s = pres.addSlide({ masterName: "CONTENT", sectionTitle: "Build and run" });
  s.addText("Deploy and operate", { placeholder: "title" });
  const dep = [
    ["Edit placeholders", "Recipients, Teams URL, Slack path, PagerDuty key"],
    ["Deploy in order", "deploy/deploy_all.sql with SnowSQL, or Snowflake CLI"],
    ["Test channels", "CALL SP_QM_TEST_CHANNELS()"],
    ["Test end to end", "SYSTEM$WAIT and a two-session lock"],
    ["Start schedule", "Resume TASK_QM_SCAN"],
  ];
  dep.forEach((d, i) => {
    const y = 1.5 + i * 1.0;
    s.addShape(S.OVAL, { x: 0.6, y, w: 0.62, h: 0.62, fill: { color: C.accent1 }, line: { color: C.accent1 }, objectName: "deploy badge " + (i + 1) });
    s.addText(String(i + 1), { x: 0.6, y, w: 0.62, h: 0.62, fontSize: 18, bold: true, color: C.background1, align: "center", valign: "middle", margin: 0, isTextBox: true });
    s.addText([{ text: d[0], options: { bold: true, breakLine: true, fontSize: 15, color: C.text2 } }, { text: d[1], options: { fontSize: 12, color: C.text1 } }],
      { x: 1.4, y: y - 0.12, w: 5.2, h: 0.86, valign: "middle", margin: 0, isTextBox: true });
  });
  box(s, 7.0, 1.45, 5.7, 5.2, C.text2, C.text2, "ops panel");
  iconCircle(s, I.bell, 7.3, 1.7, 0.7, C.accent2, "ops");
  s.addText("Day-2 operations", { x: 8.15, y: 1.7, w: 4.3, h: 0.7, fontSize: 18, bold: true, color: C.background1, valign: "middle", margin: 0, isTextBox: true });
  s.addText([
    { text: "SELECT * FROM V_QM_OPEN_ALERTS;", options: { breakLine: true } },
    { text: "SELECT * FROM V_QM_MONITOR_HEALTH;", options: { breakLine: true } },
    { text: "SELECT SYSTEM$CANCEL_QUERY('{query_id}');", options: { breakLine: true } },
    { text: "SELECT SYSTEM$ABORT_TRANSACTION({txn_id});", options: { breakLine: true } },
    { text: "UPDATE QM_CONFIG SET PARAM_VALUE = '20'", options: { breakLine: true } },
    { text: "  WHERE PARAM_NAME = 'LONG_RUNNING_MIN';", options: {} },
  ], { x: 7.3, y: 2.6, w: 5.15, h: 2.5, fontFace: "Courier New", fontSize: 12, color: C.accent5, valign: "top", paraSpaceAfter: 6, margin: 0, isTextBox: true });
  s.addText("Runbook: re-run the MONITOR grant for new warehouses. The task auto-suspends after 10 consecutive failures; review monitor health weekly.",
    { x: 7.3, y: 5.3, w: 5.15, h: 1.1, fontSize: 12, italic: true, color: C.background1, valign: "top", margin: 0, isTextBox: true });
  s.addNotes("Repository: github.com/CloudKatasani/Observability-Snowflake-Query-Alerts");

  await pres.writeFile({ fileName: OUT });
  if (process.env.APPLY_THEME) {
    const { applyTheme } = require(process.env.APPLY_THEME);
    await applyTheme(OUT, THEME);
  }
  console.log("Wrote " + OUT);
})();
