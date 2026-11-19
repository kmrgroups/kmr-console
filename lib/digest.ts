import "server-only";
import type { Brand } from "@/lib/mail";

/**
 * Daily management mail: turns the figures of console.digest_kpis (migration 0128) into ONE mail that can be understood in a few minutes:
 *   1. a scoreboard (how many areas need ACTION / WATCH / are ON TRACK),
 *   2. "Management: where to concentrate" and "Teams: what to do today",
 *   3. one small dashboard per app, each with a status in WORDS (not colour alone), the standard it supports, and a link to open the app.
 * Statuses are rule based (thresholds below; the targets can be changed per plant in Administration › Daily management mail).
 * Every value that goes into the HTML is escaped here; the finished HTML is passed to sendMail as `html`.
 */
export type St = "ok" | "watch" | "act";
export type Targets = { eff_target?: number; attendance_target?: number; despatch_target?: number; cal_days?: number };
export const DEFAULTS = { eff_target: 85, attendance_target: 92, despatch_target: 95, cal_days: 14 };
export const SECTION_KEYS = ["production", "delivery", "dcg", "calibration", "maintenance", "hrm", "actions", "meetings", "audit", "invoicing", "rmp"] as const;
export type SectionKey = (typeof SECTION_KEYS)[number];

/* eslint-disable @typescript-eslint/no-explicit-any */
type K = Record<string, any>;
type Tile = { label: string; value: string; sub?: string; st?: St };
export type Section = {
  key: string; title: string; std: string; st: St; tiles: Tile[]; html?: string; open?: string;
  mgmt: string[];                                     // management: where to concentrate
  team: { who: string; text: string }[];              // teams: what to do today
  good?: string[];                                    // what is OK
};

export const COL: Record<St, { bg: string; fg: string; bar: string; word: string }> = {
  act: { bg: "#FDECEA", fg: "#B3261E", bar: "#D93025", word: "ACTION" },
  watch: { bg: "#FFF4DB", fg: "#8A5A00", bar: "#F0A500", word: "WATCH" },
  ok: { bg: "#E6F4EA", fg: "#1E6B3A", bar: "#2E9E5B", word: "ON TRACK" },
};
export const RANK: Record<St, number> = { act: 2, watch: 1, ok: 0 };
export const worst = (...s: St[]): St => s.reduce((a, b) => (RANK[b] > RANK[a] ? b : a), "ok" as St);

export const esc = (s: unknown) => String(s ?? "").replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]!));
export const nf = (n: number | null | undefined, d = 0) => (n === null || n === undefined || Number.isNaN(Number(n)) ? "–" : Number(n).toLocaleString("en-IN", { maximumFractionDigits: d, minimumFractionDigits: d }));
export const pct = (n: number | null | undefined, d = 0) => (n === null || n === undefined ? "–" : nf(n, d) + "%");
export const dmy = (d?: string | null) => (d ? String(d).slice(0, 10).split("-").reverse().join("-") : "–");
export const dshort = (d: string) => { const [, m, dd] = d.split("-"); return `${dd}-${m}`; };
export const ago = (iso: string | null | undefined, today: string) => (iso ? Math.round((Date.parse(today) - Date.parse(iso)) / 86_400_000) : null);
export const money = (n: number) => (n >= 1e7 ? "₹" + nf(n / 1e7, 2) + " Cr" : n >= 1e5 ? "₹" + nf(n / 1e5, 2) + " L" : "₹" + nf(n));

export function tile(t: Tile) {
  const c = COL[t.st ?? "ok"], edge = t.st ? c.bar : "#c9d1de";
  return `<td valign="top" style="padding:0 6px 8px 0;width:25%"><table role="presentation" width="100%" style="border-collapse:collapse;background:#f7f8fb;border-left:4px solid ${edge}"><tr><td style="padding:8px 10px">
<div style="font-size:11px;color:#5e6778;text-transform:uppercase;letter-spacing:.03em">${esc(t.label)}</div>
<div style="font-size:21px;font-weight:700;color:#0b1c3a;line-height:1.25">${esc(t.value)}</div>${t.sub ? `<div style="font-size:11px;color:#5e6778">${esc(t.sub)}</div>` : ""}</td></tr></table></td>`;
}
export function tiles(ts: Tile[]) {
  const rows: string[] = [];
  for (let i = 0; i < ts.length; i += 4) rows.push(`<tr>${ts.slice(i, i + 4).map(tile).join("")}${"<td></td>".repeat(Math.max(0, 4 - ts.slice(i, i + 4).length))}</tr>`);
  return `<table role="presentation" width="100%" style="border-collapse:collapse;margin:8px 0 4px">${rows.join("")}</table>`;
}
/** A horizontal bar made of table cells (works in every mail program, no images). */
export function bar(value: number | null, max: number, st: St, label: string, right: string) {
  const w = value === null ? 0 : Math.max(2, Math.min(100, Math.round((value / max) * 100)));
  return `<tr><td style="padding:3px 8px 3px 0;font-size:12px;color:#344054;white-space:nowrap;width:78px">${esc(label)}</td>
<td style="padding:3px 0"><table role="presentation" width="100%" style="border-collapse:collapse;background:#eef0f4"><tr>${value === null ? `<td style="height:12px;font-size:1px;line-height:1px">&nbsp;</td>` : `<td width="${w}%" style="height:12px;background:${COL[st].bar};font-size:1px;line-height:1px">&nbsp;</td><td style="font-size:1px">&nbsp;</td>`}</tr></table></td>
<td style="padding:3px 0 3px 8px;font-size:12px;font-weight:700;color:#0b1c3a;white-space:nowrap;width:70px;text-align:right">${esc(right)}</td></tr>`;
}
export const barTable = (rows: string[]) => `<table role="presentation" width="100%" style="border-collapse:collapse;margin:4px 0 8px">${rows.join("")}</table>`;
export const mini = (h: string, rows: string[][]) => rows.length
  ? `<div style="font-size:12px;font-weight:700;color:#0b1c3a;margin:10px 0 3px">${esc(h)}</div><table role="presentation" width="100%" style="border-collapse:collapse;font-size:12px">${rows.map((r) => `<tr>${r.map((c, i) => `<td style="padding:3px ${i ? 0 : 8}px 3px 0;border-bottom:1px solid #eef0f4;color:${i ? "#344054" : "#0b1c3a"}${i ? "" : ";font-weight:600"}">${esc(c)}</td>`).join("")}</tr>`).join("")}</table>` : "";

/* ------------------------------------------------------------------ sections ------------------------------------------------------------------ */
function production(k: K, T: Required<Targets>, today: string): Section {
  const mtd = k.mtd || {}, last = k.last_day || {}, sc = k.mtd_scrap || {};
  const lagDays = ago(k.last_date, today);
  const eff: number | null = mtd.eff ?? null, effLast: number | null = last.eff ?? null;
  const effSt = (v: number | null): St => (v === null ? "watch" : v >= T.eff_target ? "ok" : v >= T.eff_target - 15 ? "watch" : "act");
  // Entries for a day are keyed in the ERP during the next day, so at the morning mail a 2-day gap is normal; flag from 3 days (watch) and 4 days (act)
  const stale: St = lagDays === null ? "act" : lagDays >= 4 ? "act" : lagDays >= 3 ? "watch" : "ok";
  const rejPct = sc.qty + sc.scrap > 0 ? (100 * sc.scrap) / (sc.qty + sc.scrap) : null;
  const rejSt: St = rejPct === null || sc.scrap === 0 ? "ok" : rejPct <= 1 ? "ok" : rejPct <= 3 ? "watch" : "act";
  const machines: { m: string; eff: number; hours: number }[] = k.machines || [];
  const below = machines.filter((x) => x.eff < T.eff_target).length;
  const days: { d: string; eff: number | null; machines: number; qty: number | null }[] = k.days || [];
  const st = worst(effSt(eff), stale, rejSt);
  const tl: Tile[] = [
    { label: "Efficiency · month to date", value: pct(eff, 1), sub: `target ${T.eff_target}%${k.prev_month_eff != null ? ` · last month ${pct(k.prev_month_eff, 1)}` : ""}`, st: effSt(eff) },
    { label: `Efficiency · last entry ${dmy(k.last_date)}`, value: pct(effLast, 1), sub: `${nf(last.machines)} machines · ${nf(last.qty)} pcs`, st: effSt(effLast) },
    { label: "Output · month to date", value: nf(sc.qty), sub: `${nf(mtd.days)} production days · ${nf(mtd.machines)} machines` },
    { label: "Rejection · month to date", value: rejPct === null ? "–" : pct(rejPct, 2), sub: `${nf(sc.scrap)} pcs scrap`, st: rejSt },
  ];
  // today and yesterday are keyed in the ERP during the next day: do not show them as "no entry"
  const shownDays = days.filter((x) => !(x.eff === null && (!k.last_date || x.d > k.last_date) && (ago(x.d, today) ?? 9) <= 1));
  const dayRows = shownDays.map((x) => bar(x.eff, 100, effSt(x.eff), dshort(x.d), x.eff === null ? "no entry" : pct(x.eff, 1)));
  const worstM = machines.slice(0, 8), bestM = machines.length > 8 ? machines.slice(-3) : [];
  const mRows = [...worstM, ...bestM.filter((b) => !worstM.includes(b))].map((x) => bar(x.eff, 100, effSt(x.eff), x.m, pct(x.eff, 1)));
  let html = tiles(tl);
  html += `<div style="font-size:12px;font-weight:700;color:#0b1c3a;margin:10px 0 0">Day-wise efficiency · last 7 days <span style="font-weight:400;color:#5e6778">(target ${T.eff_target}%)</span></div>${barTable(dayRows)}`;
  if (machines.length) html += `<div style="font-size:12px;font-weight:700;color:#0b1c3a;margin:10px 0 0">Machine-wise efficiency · month to date <span style="font-weight:400;color:#5e6778">(lowest first; ${below} of ${machines.length} machines below target)</span></div>${barTable(mRows)}`;
  if (k.loss?.length) html += mini("Top downtime reasons this month", k.loss.map((l: any) => [l.reason, `${nf(l.min / 60, 1)} h`]));
  if (k.live) html += mini("Live route-sheet entries this month", [["OK pieces", nf(k.live.ok)], ["Rejected", nf(k.live.rej)], ["Rework", nf(k.live.rew)]]);
  html += `<div style="font-size:11px;color:#5e6778;margin-top:6px">Efficiency = hours-weighted average of the ERP production entries that have an efficiency. Days with no entry are shown empty.</div>`;
  const mgmt: string[] = [], team: Section["team"] = [], good: string[] = [];
  if (stale !== "ok") { mgmt.push(`Latest production entry is for ${dmy(k.last_date)} (${lagDays ?? "many"} days ago); nothing has been keyed for the days after it. Find out whether the ERP link or the entry discipline has stopped.`); team.push({ who: "Production", text: "Complete the missing production entries today so the efficiency is real." }); }
  if (eff !== null && effSt(eff) !== "ok") {
    mgmt.push(`Efficiency this month is ${pct(eff, 1)} against the ${T.eff_target}% target${machines.length ? `; ${below} of ${machines.length} machines are below target` : ""}. Review the biggest losses with the plant head.`);
    const w = worstM.slice(0, 3).map((x) => `${x.m} (${pct(x.eff, 0)})`).join(", ");
    if (w) team.push({ who: "Production", text: `Start with the lowest machines: ${w}. Check set-up time, tool changes and waiting for material.` });
  } else if (eff !== null) good.push(`Efficiency ${pct(eff, 1)} is at or above the ${T.eff_target}% target.`);
  if (effLast !== null && eff !== null && effLast < eff - 10) { mgmt.push(`Last entry day (${dmy(k.last_date)}) fell to ${pct(effLast, 1)}, well below the month's ${pct(eff, 1)}.`); team.push({ who: "Production", text: `Find what went wrong on ${dmy(k.last_date)} and fix it today.` }); }
  if (rejSt !== "ok") { mgmt.push(`Rejection is ${pct(rejPct, 2)} of output this month.`); team.push({ who: "Quality", text: "Review the top rejection reasons and contain the affected parts." }); }
  return { key: "production", title: "Production efficiency", std: "IATF 16949 §8.5.1 control of production, §9.1.1 monitoring · VDA 6.3 P6 · ISO 9001 §8.5.1", st, tiles: tl, html, open: "mmd", mgmt, team, good };
}

function delivery(k: K, T: Required<Targets>, today: string): Section {
  const dim = new Date(Date.UTC(+today.slice(0, 4), +today.slice(5, 7), 0)).getUTCDate(), dayNo = +today.slice(8, 10);
  const elapsed = (100 * dayNo) / dim, done = k.demand > 0 ? (100 * k.despatched) / k.demand : 0;
  const ratio = elapsed > 0 ? done / elapsed : 1;
  const paceSt: St = ratio >= T.despatch_target / 100 ? "ok" : ratio >= 0.8 ? "watch" : "act";
  const lateSt: St = k.late_lines === 0 ? "ok" : k.late_lines >= 5 ? "act" : "watch";
  const actSt: St = k.actions_overdue > 0 ? "watch" : "ok";
  const st = worst(paceSt, lateSt, actSt);
  const tl: Tile[] = [
    { label: "Despatched · month to date", value: pct(done, 0), sub: `${nf(k.despatched)} of ${nf(k.demand)} pcs · month ${pct(elapsed, 0)} over`, st: paceSt },
    { label: "Value despatched", value: money(k.value_despatched), sub: `of ${money(k.value_demand)} planned` },
    { label: "Past-due lines", value: nf(k.late_lines), sub: `of ${nf(k.lines)} plan lines`, st: lateSt },
    { label: "Last despatch", value: dmy(k.last_despatch), sub: `${nf(k.lines_complete)} lines complete` },
  ];
  let html = tiles(tl);
  html += mini("Most overdue lines (due date passed, quantity still pending)", (k.late_top || []).map((x: any) => [`${x.buyer || "–"} · ${x.part}`, `due ${dmy(x.due)} · ${nf(x.short)} pcs pending`]));
  if (k.actions_open) html += `<div style="font-size:12px;color:#344054;margin-top:6px">Delivery actions open: <b>${nf(k.actions_open)}</b>${k.actions_overdue ? `, <b style="color:#B3261E">${nf(k.actions_overdue)} past target date</b>` : ""}.</div>`;
  const mgmt: string[] = [], team: Section["team"] = [], good: string[] = [];
  if (paceSt !== "ok") { mgmt.push(`Despatch is ${pct(done, 0)} of the month's plan while ${pct(elapsed, 0)} of the month has passed. Agree a catch-up plan for the late customers.`); team.push({ who: "Production / Despatch", text: "Prioritise the past-due lines; confirm the date each will ship." }); } else good.push(`Despatch is on pace (${pct(done, 0)} done, ${pct(elapsed, 0)} of the month gone).`);
  if (k.late_lines > 0) { mgmt.push(`${nf(k.late_lines)} plan line${k.late_lines === 1 ? " is" : "s are"} past the due date. Tell the customers early, with a firm date.`); team.push({ who: "Sales / Planning", text: "Call the customers of the past-due lines and update the despatch plan." }); }
  if (k.actions_overdue > 0) team.push({ who: "Action owners", text: `${nf(k.actions_overdue)} delivery action${k.actions_overdue === 1 ? "" : "s"} passed the target date: close or re-plan them.` });
  return { key: "delivery", title: "Delivery to customers", std: "IATF 16949 §9.1.2 customer satisfaction (on-time delivery) · §8.2.1 customer communication", st, tiles: tl, html, open: "sales", mgmt, team, good };
}

function dcg(k: K): Section {
  const odSt: St = k.dc_overdue === 0 ? "ok" : k.dc_overdue > 5 || k.dc_overdue_max_days > 30 ? "act" : "watch";
  const poSt: St = k.po_open_90 > 0 ? "act" : k.po_open_30 > 0 ? "watch" : "ok";
  const dSt: St = k.dc_draft_old > 0 ? "watch" : "ok";
  const st = worst(odSt, poSt, dSt);
  const tl: Tile[] = [
    { label: "Delivery challans overdue", value: nf(k.dc_overdue), sub: k.dc_overdue ? `oldest ${nf(k.dc_overdue_max_days)} days late` : "none past return date", st: odSt },
    { label: "Challans out, not returned", value: nf(k.dc_open), sub: k.dc_no_return_date ? `${nf(k.dc_no_return_date)} have no return date` : "returnable, still open" },
    { label: "Purchase orders open", value: nf(k.po_open), sub: `${nf(k.po_part)} part received · ${nf(k.po_open_30)} older than 30 days`, st: poSt },
    { label: "GRN this month", value: nf(k.grn_month), sub: `last GRN ${dmy(k.grn_last)}` },
  ];
  let html = tiles(tl);
  html += mini("Oldest overdue delivery challans", (k.dc_top || []).map((x: any) => [`${x.no} · ${x.party}`, `${nf(x.days)} days late · ${String(x.purpose || "").replace("_", " ")}`]));
  if (k.dc_draft_old) html += `<div style="font-size:12px;color:#344054;margin-top:6px"><b>${nf(k.dc_draft_old)}</b> draft challan${k.dc_draft_old === 1 ? "" : "s"} older than 3 days (made but never issued).</div>`;
  html += `<div style="font-size:11px;color:#5e6778;margin-top:6px">A purchase order stays open until every line is received (GRN) and the order is closed.</div>`;
  const mgmt: string[] = [], team: Section["team"] = [], good: string[] = [];
  if (k.dc_overdue > 0) { mgmt.push(`${nf(k.dc_overdue)} returnable challan${k.dc_overdue === 1 ? " is" : "s are"} overdue (oldest ${nf(k.dc_overdue_max_days)} days). Material and gauges outside the plant are at risk; ask the suppliers for dates.`); team.push({ who: "Stores / Purchase", text: "Chase the suppliers on the overdue challans and record each return with a GRN." }); } else good.push("No returnable challan is past its return date.");
  if (k.po_open_90 > 0) { mgmt.push(`${nf(k.po_open_90)} purchase order${k.po_open_90 === 1 ? " is" : "s are"} open for more than 90 days.`); team.push({ who: "Purchase", text: "Close the orders already received, and chase or cancel the rest." }); } else if (k.po_open_30 > 0) team.push({ who: "Purchase", text: `${nf(k.po_open_30)} order${k.po_open_30 === 1 ? "" : "s"} open for over 30 days: confirm delivery dates.` });
  if (k.dc_draft_old > 0) team.push({ who: "Stores", text: "Issue or delete the old draft challans." });
  return { key: "dcg", title: "Delivery challan & GRN", std: "IATF 16949 §8.4.2 control of external providers and outsourced processes · ISO 9001 §8.4.2", st, tiles: tl, html, open: "dcg", mgmt, team, good };
}

function calibration(k: K): Section {
  const compliance = k.in_use > 0 ? (100 * (k.in_use - k.overdue)) / k.in_use : 100;
  const st = worst(k.overdue - k.overdue_on_dc > 0 || k.oot_open > 0 ? "act" : "ok", k.overdue_on_dc > 0 || k.due_soon > 0 ? "watch" : "ok");
  const notOnDc = k.overdue - k.overdue_on_dc;
  const tl: Tile[] = [
    { label: "Gauges in calibration", value: pct(compliance, 1), sub: `${nf(k.in_use - k.overdue)} of ${nf(k.in_use)} gauges in date`, st: notOnDc > 0 ? "act" : "ok" },
    { label: "Overdue · not sent", value: nf(notOnDc), sub: k.critical_overdue ? `${nf(k.critical_overdue)} critical gauges overdue` : "past due date", st: notOnDc > 0 ? "act" : "ok" },
    { label: `Due in ${k.due_days} days`, value: nf(k.due_soon), sub: "plan calibration now", st: k.due_soon > 0 ? "watch" : "ok" },
    { label: "Out for calibration", value: nf(k.on_dc), sub: `${nf(k.oot_open)} out-of-tolerance cases open`, st: k.oot_open > 0 ? "act" : undefined },
  ];
  let html = tiles(tl);
  // the same list the Calibration Hub due-date mail carries: gauges going overdue within the alert window (gauges already on a challan are left out)
  const due = (k.due_list || []) as any[];
  html += mini(`Gauges going to overdue within ${k.due_days} days${k.due_soon > due.length ? ` (first ${nf(due.length)} of ${nf(k.due_soon)})` : ""}`, due.map((x) => [
    `${x.tag} · ${x.name}`,
    `Due ${dmy(x.next_due)} (${nf(x.days_left)} day${x.days_left === 1 ? "" : "s"}) · ${x.gauge_class ?? "Variable"}${x.location ? " · " + x.location : x.department ? " · " + x.department : ""}${x.supplier ? " · Supplier: " + x.supplier : ""}`]));
  if (k.due_soon > 0 && !due.length) html += `<div style="font-size:12px;color:#344054;margin-top:6px">Open Calibration Hub for the list of gauges due in ${k.due_days} days.</div>`;
  html += mini("Longest overdue gauges (not yet sent for calibration)", (k.top || []).map((x: any) => [`${x.tag} · ${x.name}`, `${nf(x.days)} days overdue`]));
  if (k.no_due_date) html += `<div style="font-size:12px;color:#344054;margin-top:6px"><b>${nf(k.no_due_date)}</b> gauges have no due date entered.</div>`;
  const mgmt: string[] = [], team: Section["team"] = [], good: string[] = [];
  if (notOnDc > 0) { mgmt.push(`${nf(notOnDc)} gauge${notOnDc === 1 ? " is" : "s are"} past the calibration date and still in use${k.critical_overdue ? ` (${nf(k.critical_overdue)} critical)` : ""}. Measurements made with them cannot be trusted.`); team.push({ who: "Quality / Calibration", text: "Send the overdue gauges for calibration this week; stop using critical ones until done. Check parts measured with them." }); } else good.push("No gauge in use is past its calibration date.");
  if (k.oot_open > 0) { mgmt.push(`${nf(k.oot_open)} out-of-tolerance case${k.oot_open === 1 ? "" : "s"} open: product measured with these gauges needs an impact check.`); team.push({ who: "Quality", text: "Finish the impact assessment of the open out-of-tolerance cases." }); }
  if (k.due_soon > 0) team.push({ who: "Quality / Calibration", text: `Send the ${nf(k.due_soon)} gauge${k.due_soon === 1 ? "" : "s"} due in ${k.due_days} days with a challan before the date passes.` });
  return { key: "calibration", title: "Calibration of gauges", std: "IATF 16949 §7.1.5.2 measurement traceability · ISO 9001 §7.1.5 · MSA 4th edition", st, tiles: tl, html, open: "calib", mgmt, team, good };
}

function maintenance(k: K): Section {
  const bdSt: St = k.open === 0 ? "ok" : k.oldest_open_hrs > 24 ? "act" : "watch";
  const pmSt: St = k.pm_overdue === 0 ? "ok" : k.pm_plans > 0 && k.pm_overdue / k.pm_plans > 0.2 ? "act" : "watch";
  const st = worst(bdSt, pmSt);
  const tl: Tile[] = [
    { label: "Breakdowns open now", value: nf(k.open), sub: k.open ? `oldest ${nf(k.oldest_open_hrs)} hours` : "none", st: bdSt },
    { label: "Breakdowns this month", value: nf(k.month_count), sub: `${nf(k.month_down_hrs, 1)} h down · repair time ${k.mttr_hrs == null ? "–" : nf(k.mttr_hrs, 1) + " h"}` },
    { label: "Preventive maintenance overdue", value: nf(k.pm_overdue), sub: `of ${nf(k.pm_plans)} plans`, st: pmSt },
    { label: "PM due next 7 days", value: nf(k.pm_week) },
  ];
  let html = tiles(tl);
  html += mini("Breakdowns still open", (k.top || []).map((x: any) => [`${x.no} · ${x.machine}`, `${nf(x.hrs)} h · ${x.problem}`]));
  const mgmt: string[] = [], team: Section["team"] = [], good: string[] = [];
  if (k.open > 0) { mgmt.push(`${nf(k.open)} breakdown${k.open === 1 ? " is" : "s are"} open${k.oldest_open_hrs > 24 ? `, the oldest for ${nf(k.oldest_open_hrs)} hours` : ""}. Ensure spares and people are available.`); team.push({ who: "Maintenance", text: "Close the open breakdowns, record cause and action; book the lost time." }); } else good.push("No machine is down.");
  if (k.pm_overdue > 0) { mgmt.push(`${nf(k.pm_overdue)} preventive maintenance task${k.pm_overdue === 1 ? " is" : "s are"} overdue; breakdowns follow late PM.`); team.push({ who: "Maintenance", text: "Complete the overdue preventive maintenance, starting with critical machines." }); } else if (k.pm_plans) good.push("Preventive maintenance is up to date.");
  return { key: "maintenance", title: "Maintenance", std: "IATF 16949 §8.5.1.5 total productive maintenance · ISO 9001 §7.1.3", st, tiles: tl, html, open: "mnt", mgmt, team, good };
}

function hrm(k: K, T: Required<Targets>, today: string): Section {
  const counted = k.present + k.half + k.absent + k.leave + k.missing_punch;
  const attPct = counted > 0 ? (100 * (k.present + 0.5 * k.half)) / counted : null;
  const stale = ago(k.att_date, today) ?? 0;
  const aSt: St = attPct === null ? "watch" : attPct >= T.attendance_target ? "ok" : attPct >= T.attendance_target - 5 ? "watch" : "act";
  const fSt: St = stale >= 2 ? "act" : stale === 1 ? "watch" : "ok";
  const st = worst(aSt, fSt, k.missing_punch > 0 ? "watch" : "ok");
  const tl: Tile[] = [
    { label: `Attendance · ${dmy(k.att_date)}`, value: pct(attPct, 1), sub: `target ${T.attendance_target}%`, st: aSt },
    { label: "Present / absent", value: `${nf(k.present)} / ${nf(k.absent)}`, sub: `${nf(k.leave)} on leave · ${nf(k.half)} half day`, st: aSt === "act" ? "act" : undefined },
    { label: "Late arrivals", value: nf(k.late), sub: `${nf(k.missing_punch)} missing punches`, st: k.missing_punch > 0 ? "watch" : undefined },
    { label: "Overtime", value: nf(k.ot_hrs_day, 1) + " h", sub: `${nf(k.ot_hrs_month)} h this month` },
  ];
  const days: { d: string; pct: number }[] = k.days || [];
  let html = tiles(tl);
  if (days.length > 1) html += `<div style="font-size:12px;font-weight:700;color:#0b1c3a;margin:10px 0 0">Attendance · last days</div>${barTable(days.map((x) => bar(x.pct, 100, x.pct >= T.attendance_target ? "ok" : x.pct >= T.attendance_target - 5 ? "watch" : "act", dshort(x.d), pct(x.pct, 1))))}`;
  const mgmt: string[] = [], team: Section["team"] = [], good: string[] = [];
  if (stale >= 1) { mgmt.push(`Attendance has not been updated since ${dmy(k.att_date)}.`); team.push({ who: "HR", text: "Update attendance (biometric import) so today's manpower is known." }); }
  if (aSt === "act") { mgmt.push(`Attendance on ${dmy(k.att_date)} was ${pct(attPct, 1)} against ${T.attendance_target}%. ${nf(k.absent)} people absent without leave: check the departments affected.`); team.push({ who: "Department heads", text: "Re-plan manpower for the absentees and confirm the reasons." }); } else if (aSt === "watch") team.push({ who: "HR", text: `Attendance is a little under target (${pct(attPct, 1)}); follow up the ${nf(k.absent)} absentees.` }); else good.push(`Attendance ${pct(attPct, 1)} is at target.`);
  if (k.missing_punch > 0) team.push({ who: "HR", text: `Correct ${nf(k.missing_punch)} missing punch${k.missing_punch === 1 ? "" : "es"} before payroll.` });
  return { key: "hrm", title: "People & attendance", std: "ISO 9001 §7.1.2 people, §7.2 competence · IATF 16949 §7.2", st, tiles: tl, html, open: "hrms", mgmt, team, good };
}

function actions(k: K): Section {
  const st: St = k.urgent_overdue > 0 || k.overdue >= 5 ? "act" : k.overdue > 0 || k.blocked > 0 ? "watch" : "ok";
  const tl: Tile[] = [
    { label: "Actions overdue", value: nf(k.overdue), sub: `of ${nf(k.open)} open`, st: k.overdue > 0 ? (st === "act" ? "act" : "watch") : "ok" },
    { label: "Urgent / high overdue", value: nf(k.urgent_overdue), st: k.urgent_overdue > 0 ? "act" : "ok" },
    { label: "Due today", value: nf(k.due_today), sub: `${nf(k.blocked)} blocked`, st: k.blocked > 0 ? "watch" : undefined },
    { label: "Closed this month", value: nf(k.done_month) },
  ];
  let html = tiles(tl);
  html += mini("Longest overdue actions", (k.top || []).map((x: any) => [`${x.no} · ${x.title}`, `${x.who} · ${nf(x.days)} days late`]));
  const mgmt: string[] = [], team: Section["team"] = [], good: string[] = [];
  if (k.overdue > 0) { mgmt.push(`${nf(k.overdue)} action${k.overdue === 1 ? " is" : "s are"} overdue${k.urgent_overdue ? `, ${nf(k.urgent_overdue)} of them urgent or high priority` : ""}. Ask the owners for a date or reassign.`); team.push({ who: "Action owners", text: "Close or re-plan your overdue actions today; say why if blocked." }); } else good.push("No action is overdue.");
  if (k.blocked > 0) mgmt.push(`${nf(k.blocked)} action${k.blocked === 1 ? " is" : "s are"} blocked and need${k.blocked === 1 ? "s" : ""} a decision or support.`);
  return { key: "actions", title: "Actions (ActionTrack)", std: "ISO 9001 §10.2 nonconformity and corrective action, §10.3 improvement · IATF 16949 §10.2.3 problem solving", st, tiles: tl, html, open: "tsk", mgmt, team, good };
}

function meetings(k: K): Section {
  const st: St = k.overdue >= 5 ? "act" : k.overdue > 0 ? "watch" : "ok";
  const tl: Tile[] = [{ label: "Meeting actions open", value: nf(k.open) }, { label: "Past their date", value: nf(k.overdue), st }];
  const mgmt: string[] = [], team: Section["team"] = [], good: string[] = [];
  if (k.overdue > 0) { mgmt.push(`${nf(k.overdue)} action${k.overdue === 1 ? "" : "s"} from meetings passed the agreed date.`); team.push({ who: "Meeting action owners", text: "Report the status of your meeting actions and give a new date if needed." }); } else good.push("Meeting actions are on time.");
  return { key: "meetings", title: "Meeting minutes", std: "ISO 9001 §9.3 management review · §7.4 communication", st, tiles: tl, open: "mom", mgmt, team, good, html: tiles(tl) };
}

function audit(k: K): Section {
  const st: St = k.major_open > 0 || k.overdue > 0 ? "act" : k.open > 0 ? "watch" : "ok";
  const tl: Tile[] = [{ label: "Audit findings open", value: nf(k.open), st: k.open > 0 ? "watch" : "ok" }, { label: "Major findings open", value: nf(k.major_open), st: k.major_open > 0 ? "act" : "ok" }, { label: "Past response date", value: nf(k.overdue), st: k.overdue > 0 ? "act" : "ok" }];
  const mgmt: string[] = [], team: Section["team"] = [], good: string[] = [];
  if (k.major_open > 0) mgmt.push(`${nf(k.major_open)} major audit finding${k.major_open === 1 ? " is" : "s are"} still open. Check containment and root cause are on time.`);
  if (k.overdue > 0) team.push({ who: "Finding owners", text: `${nf(k.overdue)} finding${k.overdue === 1 ? "" : "s"} past the response or action date: complete containment, root cause and action.` });
  if (!k.open) good.push("No audit finding is open.");
  return { key: "audit", title: "Internal audit findings", std: "IATF 16949 §9.2 internal audit · VDA 6.3 · ISO 9001 §9.2, §10.2", st, tiles: tl, open: "aud", mgmt, team, good, html: tiles(tl) };
}

function invoicing(k: K, today: string): Section {
  const stale = ago(k.last_date, today);
  const st: St = k.drafts_old > 0 || (stale !== null && stale >= 4) ? "watch" : "ok";
  const tl: Tile[] = [
    { label: "Invoiced · month to date", value: money(k.month_value), sub: `${nf(k.month_count)} invoices · last month ${money(k.prev_value)}` },
    { label: "Last invoice", value: dmy(k.last_date), sub: stale !== null ? `${nf(stale)} day${stale === 1 ? "" : "s"} ago` : undefined, st: stale !== null && stale >= 4 ? "watch" : undefined },
    { label: "Old draft invoices", value: nf(k.drafts_old), sub: "older than 2 days", st: k.drafts_old > 0 ? "watch" : "ok" },
  ];
  const mgmt: string[] = [], team: Section["team"] = [], good: string[] = [];
  if (k.drafts_old > 0) team.push({ who: "Accounts", text: `Issue or delete the ${nf(k.drafts_old)} draft invoice${k.drafts_old === 1 ? "" : "s"} older than 2 days.` });
  if (stale !== null && stale >= 4) mgmt.push(`No invoice has been issued for ${nf(stale)} days. Check that despatches are being invoiced.`);
  return { key: "invoicing", title: "Invoicing", std: "ISO 9001 §8.2.4 / §8.6 release of products · order-to-cash control", st, tiles: tl, open: "inv", mgmt, team, good, html: tiles(tl) };
}

/* ------------------------------------------------------------------ the mail ------------------------------------------------------------------ */
export type DigestInput = {
  slug: string; company: string; brand?: Brand; sections?: Record<string, boolean>; targets?: Targets; kpis: Record<string, K>; today?: string; test?: boolean;
  platformUrl: string;
};

const FORMAT = "Format F-DMR-01 · Rev 00 · 16-11-2026";
const HOME: Record<string, string> = { mmd: "mmd.html", sales: "sales.html", dcg: "dcg.html", calib: "calibration.html", inv: "inv.html", rmp: "rmp.html", pnl: "pnl.html", bud: "bud.html", ppl: "ppl.html", mlp: "mlp.html" };

function rmp(k: K, today: string): Section {
  const pd = k.plan_qty_td > 0 ? Math.round((100 * k.recv_qty_td) / k.plan_qty_td) : null;   // received against what was planned in weeks already over
  const recSt: St = pd === null ? "ok" : pd >= 95 ? "ok" : pd >= 80 ? "watch" : "act";
  const lateSt: St = k.delayed === 0 ? "ok" : k.delayed >= 3 ? "act" : "watch";
  const stkSt: St = k.below_safety === 0 ? "ok" : k.below_safety >= 3 ? "act" : "watch";
  const ordSt: St = k.orders_late === 0 ? "ok" : "act";
  const stale = ago(k.updated_on, today);
  const st = worst(recSt, lateSt, stkSt, ordSt);
  const tl: Tile[] = [
    { label: "Received vs plan (weeks over)", value: pd === null ? "–" : pct(pd), sub: `${nf(k.recv_qty_td)} of ${nf(k.plan_qty_td)} planned`, st: pd === null ? undefined : recSt },
    { label: "Materials behind plan", value: nf(k.delayed), sub: `of ${nf(k.materials)} materials`, st: lateSt },
    { label: "Below safety stock", value: nf(k.below_safety), st: stkSt },
    { label: "Orders past due date", value: nf(k.orders_late), sub: `${nf(k.orders_open)} open order${k.orders_open === 1 ? "" : "s"}`, st: k.orders_open ? ordSt : undefined },
    { label: "Plan value to date", value: "₹" + nf(k.plan_lakh_td, 2) + " L", sub: `month ₹${nf(k.plan_lakh, 2)} L` },
    { label: "Actual value to date", value: "₹" + nf(k.actual_lakh, 2) + " L", sub: `weeks over ₹${nf(k.actual_lakh_td, 2)} L vs ₹${nf(k.plan_lakh_td, 2)} L` },
    { label: "Weeks over", value: nf(k.elapsed_weeks) + " of 5", sub: "week 1 = days 1-7 of the month" },
    { label: "Plan last updated", value: dmy(k.updated_on), sub: stale === null ? undefined : stale === 0 ? "today" : `${stale} days ago`, st: stale !== null && stale > 7 ? "watch" : undefined },
  ];
  let html = tiles(tl);
  html += mini("Behind plan (weeks already over)", (k.late || []).map((x: any) => [x.code, `received ${nf(x.recv)} of ${nf(x.plan)} ${x.unit} · short ${nf(x.short)} (${x.pct ?? 0}%)`]));
  html += mini("Below safety stock", (k.low || []).map((x: any) => [x.code, `stock ${nf(x.on_hand)} · safety ${nf(x.safety)}`]));
  html += mini("Orders past due date", (k.orders_top || []).map((x: any) => [`${x.po || "Order"} · ${x.code}`, `${nf(x.days)} days late · ${nf(x.qty)} kg`]));
  const mgmt: string[] = [], team: Section["team"] = [], good: string[] = [];
  if (pd !== null && pd < 95) { mgmt.push(`Material received is ${pct(pd)} of what the plan expected by now; production for these materials is at risk. Escalate to the suppliers.`); team.push({ who: "Purchase", text: "Call the suppliers of the late materials, get firm dates and update the weekly received quantity." }); } else if (pd !== null) good.push("Material is arriving as planned.");
  if (k.delayed > 0 && (k.late || []).length) team.push({ who: "Purchase / Stores", text: `Late: ${(k.late as any[]).slice(0, 3).map((x) => x.code).join(", ")}${k.delayed > 3 ? " and more" : ""}. Confirm what is in transit and tell Planning.` });
  if (k.below_safety > 0) { mgmt.push(`${nf(k.below_safety)} material${k.below_safety === 1 ? " is" : "s are"} below safety stock; a line stop is possible if they do not arrive.`); team.push({ who: "Stores", text: "Recount the stock of the low materials and raise purchase requests today." }); } else good.push("Every material is at or above safety stock.");
  if (k.orders_late > 0) { mgmt.push(`${nf(k.orders_late)} purchase order${k.orders_late === 1 ? " is" : "s are"} past the due date.`); team.push({ who: "Purchase", text: "Chase the overdue purchase orders and record the new promise dates." }); }
  if (k.no_rate > 0) team.push({ who: "Planning", text: `${nf(k.no_rate)} planned material${k.no_rate === 1 ? " has" : "s have"} no rate, so value is understated. Enter the rates.` });
  if (stale !== null && stale > 7) team.push({ who: "Planning", text: `The weekly received quantities were last updated ${stale} days ago. Update them so this report is true.` });
  return { key: "rmp", title: "Raw material planning", std: "IATF 16949 §8.4.2 control of external providers, §8.5.1.1 · ISO 9001 §8.4, §8.1 · VDA 6.3 P4 / P6 · APQP", st, tiles: tl, html, open: "rmp", mgmt, team, good };
}


export function buildDigest(inp: DigestInput) {
  const T: Required<Targets> = { ...DEFAULTS, ...Object.fromEntries(Object.entries(inp.targets || {}).filter(([, v]) => Number.isFinite(Number(v))).map(([k, v]) => [k, Number(v)])) } as Required<Targets>;
  const today = inp.today || new Date(Date.now() + 5.5 * 3600_000).toISOString().slice(0, 10);
  const on = (k: SectionKey) => inp.sections?.[k] !== false && inp.kpis[k];
  const S: Section[] = [];
  const kp = inp.kpis;
  if (on("production")) S.push(production(kp.production!, T, today));
  if (on("delivery")) S.push(delivery(kp.delivery!, T, today));
  if (on("dcg")) S.push(dcg(kp.dcg!));
  if (on("calibration")) S.push(calibration(kp.calibration!));
  if (on("maintenance")) S.push(maintenance(kp.maintenance!));
  if (on("hrm")) S.push(hrm(kp.hrm!, T, today));
  if (on("actions")) S.push(actions(kp.actions!));
  if (on("meetings")) S.push(meetings(kp.meetings!));
  if (on("audit")) S.push(audit(kp.audit!));
  if (on("invoicing")) S.push(invoicing(kp.invoicing!, today));
  if (on("rmp")) S.push(rmp(kp.rmp!, today));
  const missing = SECTION_KEYS.filter((k) => inp.sections?.[k] !== false && !kp[k]).map((m) => ({ production: "Production", delivery: "Delivery", dcg: "DC &amp; GRN", calibration: "Calibration", maintenance: "Maintenance", hrm: "HRM", actions: "Actions", meetings: "Meetings", audit: "Audit", invoicing: "Invoicing", rmp: "Raw material planning" }[m]));
  return compose({ S, slug: inp.slug, company: inp.company, unit: inp.brand?.plant || undefined, today, test: inp.test, platformUrl: inp.platformUrl, refPrefix: "DMR", format: FORMAT, title: "Daily management report", missing,
    mgmtTitle: "Management: where to concentrate today", teamTitle: "Teams: what to do today", settingsPath: "Administration › Daily management mail", openLabel: "Open the app" });
}

export type ComposeIn = { S: Section[]; slug: string; company: string; unit?: string; today: string; test?: boolean; platformUrl: string; refPrefix: string; format: string; title: string; missing: string[];
  mgmtTitle: string; teamTitle: string; settingsPath: string; openLabel: string; allClear?: string; noTeam?: string };
/** The common layout of both mails: scoreboard, management list, team list, what is OK, one block per area (worst first), reading guide. */
export function compose(inp: ComposeIn) {
  const { S, today } = inp;
  const count = (s: St) => S.filter((x) => x.st === s).length;
  const act = count("act"), watch = count("watch"), ok = count("ok");
  const order = [...S].sort((a, b) => RANK[b.st] - RANK[a.st]);
  const code = (inp.slug.match(/c(\d{3,5})$/i)?.[0] || inp.slug.slice(-6)).toUpperCase();
  const refNo = `${inp.refPrefix}-${code}-${today.replace(/-/g, "")}${inp.test ? "-TEST" : ""}`;
  const link = (key: string, label: string) => {
    const base = inp.platformUrl, co = encodeURIComponent(inp.slug);
    return `<a href="${esc(HOME[key] ? `${base}/it/${HOME[key]}?kmr=1&co=${co}` : `${base}/it/app/${co}`)}" style="color:#0b1c3a;font-weight:700;font-size:12px">${esc(label)} →</a>`;
  };

  const score = (st: St, n: number, label: string) => `<td width="33%" style="padding:0 6px 0 0"><table role="presentation" width="100%" style="border-collapse:collapse;background:${COL[st].bg};border-top:4px solid ${COL[st].bar}"><tr><td align="center" style="padding:10px 4px">
<div style="font-size:30px;font-weight:700;color:${COL[st].fg};line-height:1.1">${n}</div><div style="font-size:11px;font-weight:700;color:${COL[st].fg};letter-spacing:.05em">${COL[st].word}</div><div style="font-size:11px;color:#5e6778">${esc(label)}</div></td></tr></table></td>`;
  let h = `<div style="font-size:13px;color:#5e6778;margin:-4px 0 12px">${esc(dmy(today))} · figures as on this morning · read the first box and the two lists, that is the whole picture</div>`;
  h += `<table role="presentation" width="100%" style="border-collapse:collapse;margin:0 0 14px"><tr>${score("act", act, "areas need action")}${score("watch", watch, "areas to watch")}${score("ok", ok, "areas on track")}</tr></table>`;

  const mg = order.flatMap((s) => s.mgmt.slice(0, 1).map((t) => ({ s, t }))).slice(0, 7);   // the single most important point of each area, worst areas first
  h += `<table role="presentation" width="100%" style="border-collapse:collapse;margin:0 0 12px;border:1px solid #d9dfe9"><tr><td style="background:#0b1c3a;color:#fff;padding:8px 12px;font-weight:700;font-size:14px">${esc(inp.mgmtTitle)}</td></tr><tr><td style="padding:8px 12px">`;
  h += mg.length ? mg.map(({ s, t }) => `<div style="padding:5px 0;border-bottom:1px solid #eef0f4;font-size:13px;line-height:1.5"><span style="display:inline-block;background:${COL[s.st].bg};color:${COL[s.st].fg};font-weight:700;font-size:10px;padding:1px 6px;margin-right:6px">${COL[s.st].word}</span><b>${esc(s.title)}:</b> ${esc(t)}</div>`).join("")
    : `<div style="font-size:13px;padding:4px 0;color:#1E6B3A">${esc(inp.allClear || "Nothing needs management attention today. All areas below are on track.")}</div>`;
  h += `</td></tr></table>`;

  const tm = new Map<string, string[]>();
  for (const s of order) for (const x of s.team) { if (!tm.has(x.who)) tm.set(x.who, []); tm.get(x.who)!.push(x.text); }
  h += `<table role="presentation" width="100%" style="border-collapse:collapse;margin:0 0 16px;border:1px solid #d9dfe9"><tr><td style="background:#c6a15b;color:#0b1c3a;padding:8px 12px;font-weight:700;font-size:14px">${esc(inp.teamTitle)}</td></tr><tr><td style="padding:8px 12px">`;
  h += tm.size ? Array.from(tm.entries()).slice(0, 8).map(([who, ts]) => `<div style="padding:5px 0;border-bottom:1px solid #eef0f4;font-size:13px;line-height:1.5"><b>${esc(who)}</b><br>${ts.slice(0, 2).map((t) => `• ${esc(t)}`).join("<br>")}</div>`).join("") : `<div style="font-size:13px;padding:4px 0;color:#1E6B3A">${esc(inp.noTeam || "No open items for the teams today. Keep it up.")}</div>`;
  h += `</td></tr></table>`;

  const oks = S.filter((s) => s.good?.length).flatMap((s) => s.good!.map((g) => g)).slice(0, 5);
  if (oks.length) h += `<div style="font-size:12px;color:#1E6B3A;margin:0 0 14px"><b>What is OK:</b> ${oks.map(esc).join(" · ")}</div>`;

  for (const s of order) {   // worst areas first
    const c = COL[s.st];
    h += `<table role="presentation" width="100%" style="border-collapse:collapse;margin:0 0 14px;border:1px solid #d9dfe9"><tr><td style="padding:8px 12px;background:#f7f8fb;border-left:5px solid ${c.bar}">
<table role="presentation" width="100%" style="border-collapse:collapse"><tr><td style="font-size:15px;font-weight:700;color:#0b1c3a">${esc(s.title)}</td><td align="right"><span style="display:inline-block;background:${c.bg};color:${c.fg};font-weight:700;font-size:11px;padding:2px 8px;letter-spacing:.04em">${c.word}</span></td></tr></table>
<div style="font-size:11px;color:#5e6778">Standard: ${esc(s.std)}</div></td></tr><tr><td style="padding:6px 12px 8px">${s.html ?? tiles(s.tiles)}<div style="margin-top:6px">${s.open ? link(s.open, inp.openLabel) : ""}</div></td></tr></table>`;
  }
  if (inp.missing.length) h += `<div style="font-size:11px;color:#5e6778;margin:0 0 8px">Not shown (not in use, switched off or no data yet): ${inp.missing.join(", ")}.</div>`;
  h += `<div style="font-size:11px;color:#5e6778;border-top:1px solid #e6dfd1;padding-top:8px">How to read: <b style="color:${COL.act.fg}">ACTION</b> = outside target, needs someone today · <b style="color:${COL.watch.fg}">WATCH</b> = drifting, keep an eye · <b style="color:${COL.ok.fg}">ON TRACK</b> = within target. Targets and sections can be changed by your administrator (${esc(inp.settingsPath)}).</div>`;

  const subject = `${inp.test ? "TEST — " : ""}${inp.title} ${dmy(today)} — ${act ? `${act} need action` : "nothing needs action"}${watch ? `, ${watch} to watch` : ""} · ${inp.unit || inp.company}`;
  return { subject, html: h, refNo, revision: inp.format, counts: { act, watch, ok }, sections: S.length };
}
