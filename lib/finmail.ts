import "server-only";
import { COL, compose, dmy, esc, mini, nf, tiles, worst, type Section, type St } from "@/lib/digest";

/**
 * Finance mail for top management (separate from the daily management mail): sales value, receivables, payables, expenses against budget and as a % of sales,
 * cash movement. The figures come from console.fin_kpis (migration 0129); statuses are rule based and the targets can be changed in Administration › Finance mail.
 * Money is shown in rupees: ₹ lakh (L) = 1,00,000 and ₹ crore (Cr) = 1,00,00,000.
 */
/* eslint-disable @typescript-eslint/no-explicit-any */
type K = Record<string, any>;
export const FIN_KEYS = ["sales", "receivables", "payables", "expenses", "cash"] as const;
export type FinKey = (typeof FIN_KEYS)[number];
export type FinTargets = { dso_target?: number; overdue_pct_target?: number; expense_pct_target?: number | null; material_pct_target?: number | null };
export const FIN_DEFAULTS = { dso_target: 60, overdue_pct_target: 10 };
export type FinInput = { slug: string; brand?: unknown; company: string; sections?: Record<string, boolean>; targets?: FinTargets; kpis: Record<string, K>; today?: string; test?: boolean; platformUrl: string };

const FORMAT = "Format F-FIN-01 · Rev 00 · 16-11-2026";
const STD = "ISO 9001 §9.3.2 management review inputs, §6.1 risks · IATF 16949 §9.3.2.1";
const rs0 = (n: number) => (n >= 1e7 ? "₹" + nf(n / 1e7, 2) + " Cr" : n >= 1e5 ? "₹" + nf(n / 1e5, 2) + " L" : "₹" + nf(n));
const rs = (n: number | null | undefined) => (n === null || n === undefined || Number.isNaN(Number(n)) ? "–" : n < 0 ? "−" + rs0(-n) : rs0(n));
const share = (a: number, b: number) => (b > 0 ? (100 * a) / b : 0);
const num = (v: unknown): number | null => (v === null || v === undefined || v === "" || !Number.isFinite(Number(v)) ? null : Number(v));
/** red / amber / green against a target where lower is better: green up to the target, amber up to `slack` points above, red beyond. */
const lowerBetter = (v: number, target: number, slack: number): St => (v <= target ? "ok" : v <= target + slack ? "watch" : "act");

function bars(rows: { label: string; v: number | null; max: number; st: St; right: string }[]) {
  return `<table role="presentation" width="100%" style="border-collapse:collapse;margin:4px 0 8px">${rows.map((r) => {
    const w = r.v === null ? 0 : Math.max(2, Math.min(100, Math.round((r.v / (r.max || 1)) * 100)));
    return `<tr><td style="padding:3px 8px 3px 0;font-size:12px;color:#344054;white-space:nowrap;width:90px">${esc(r.label)}</td><td style="padding:3px 0;width:100%"><table role="presentation" width="100%" style="border-collapse:collapse;background:#eef0f4"><tr>${r.v === null ? `<td style="height:12px;font-size:1px">&nbsp;</td>` : `<td width="${w}%" style="height:12px;background:${COL[r.st].bar};font-size:1px;line-height:1px">&nbsp;</td><td style="font-size:1px">&nbsp;</td>`}</tr></table></td><td style="padding:3px 0 3px 8px;font-size:12px;font-weight:700;color:#0b1c3a;white-space:nowrap;text-align:right">${esc(r.right)}</td></tr>`;
  }).join("")}</table>`;
}
/** One stacked bar: how old the money is (not yet due, then days past the due date). */
function ageing(k: K) {
  const parts = [["Not yet due", k.b0, "#2E9E5B"], ["1-30 days late", k.b30, "#F0C040"], ["31-60", k.b60, "#F0A500"], ["61-90", k.b90, "#E8590C"], ["Over 90", k.b90p, "#B3261E"]] as [string, number, string][];
  const tot = parts.reduce((a, p) => a + (p[1] || 0), 0) || 1;
  const cells = parts.filter((p) => p[1] > 0).map((p) => `<td width="${Math.max(2, Math.round((100 * p[1]) / tot))}%" style="height:16px;background:${p[2]};font-size:1px;line-height:1px">&nbsp;</td>`).join("");
  const legend = parts.map((p) => `<td style="font-size:11px;color:#344054;padding:4px 10px 0 0;white-space:nowrap"><span style="display:inline-block;width:9px;height:9px;background:${p[2]}"></span> ${esc(p[0])}<br><b style="color:#0b1c3a">${rs(p[1])}</b></td>`).join("");
  return `<div style="font-size:12px;font-weight:700;color:#0b1c3a;margin:10px 0 3px">How old the money is</div><table role="presentation" width="100%" style="border-collapse:collapse;background:#eef0f4"><tr>${cells}</tr></table><table role="presentation" style="border-collapse:collapse"><tr>${legend}</tr></table>`;
}

function sales(k: K, today: string): Section {
  const dim = k.days_in_month, day = Math.max(1, k.day);
  const expected = k.prev_month > 0 ? (k.prev_month * day) / dim : null;
  const ratio = expected ? k.mtd / expected : null;
  const paceSt: St = ratio === null ? "ok" : ratio >= 0.95 ? "ok" : ratio >= 0.8 ? "watch" : "act";
  const proj = (k.mtd / day) * dim;
  const idle = k.last_date ? Math.round((Date.parse(today) - Date.parse(k.last_date)) / 86_400_000) : null;
  const idleSt: St = idle === null ? "watch" : idle > 5 && day > 5 ? "act" : idle > 3 && day > 3 ? "watch" : "ok";
  const st = worst(paceSt, idleSt);
  const tl = [
    { label: "Sales this month (before GST)", value: rs(k.mtd), sub: `day ${day} of ${dim} · ${nf(k.invoices_mtd)} invoices`, st: paceSt },
    { label: "Same period at last month's pace", value: expected === null ? "–" : rs(expected), sub: ratio === null ? "no sales last month" : `${nf(100 * ratio)}% of it reached` },
    { label: "Likely month end (at this pace)", value: rs(proj), sub: `last month ${rs(k.prev_month)}` },
    { label: "Last invoice", value: dmy(k.last_date), sub: idle === null ? undefined : idle === 0 ? "today" : `${idle} days ago`, st: idleSt },
  ];
  const mx = Math.max(1, ...(k.months || []).map((m: any) => m.v || 0));
  let html = tiles(tl);
  html += `<div style="font-size:12px;font-weight:700;color:#0b1c3a;margin:10px 0 3px">Sales by month (before GST)</div>` + bars((k.months || []).map((m: any, i: number, a: any[]) => ({ label: m.m, v: m.v === null ? null : m.v, max: mx, st: (i === a.length - 1 ? paceSt : "ok") as St, right: m.v === null ? "–" : rs(m.v) })));
  html += mini("Top customers this month", (k.top || []).map((x: any) => [x.party, rs(x.v)]));
  const mgmt: string[] = [], team: Section["team"] = [], good: string[] = [];
  if (ratio !== null && ratio < 0.95) { mgmt.push(`Sales are ${nf(100 * ratio)}% of last month's pace; at this rate the month ends near ${rs(proj)} against ${rs(k.prev_month)} last month.`); team.push({ who: "Sales and despatch", text: "Confirm which despatches are ready but not invoiced, and which customer schedules are slipping." }); } else if (ratio !== null) good.push(`Sales are on or ahead of last month's pace (${rs(k.mtd)} so far).`);
  if (idle !== null && idle > 3 && day > 3) { mgmt.push(`No invoice for ${nf(idle)} days.`); team.push({ who: "Accounts", text: "Raise invoices for goods already despatched." }); }
  return { key: "sales", title: "Sales value", std: STD + " · ISO 9001 §8.2.4", st, tiles: tl, html, open: "fin", mgmt, team, good };
}

function receivables(k: K, T: Required<Pick<FinTargets, "dso_target" | "overdue_pct_target">>, gross90: number | null): Section {
  const od = share(k.overdue, k.total);
  const odSt: St = lowerBetter(od, T.overdue_pct_target, 15);
  const dso = gross90 && gross90 > 0 ? Math.round(k.total / (gross90 / 90)) : null;
  const dsoSt: St = dso === null ? "ok" : lowerBetter(dso, T.dso_target, 15);
  const oldSt: St = k.b90p > 0 ? (share(k.b90p, k.total) > 5 ? "act" : "watch") : "ok";
  const st = worst(odSt, dsoSt, oldSt);
  const tl = [
    { label: "Receivable (customers owe us)", value: rs(k.total), sub: `${nf(k.bills)} bills` },
    { label: "Overdue", value: rs(k.overdue), sub: `${nf(od, 1)}% of receivable · target ${T.overdue_pct_target}%`, st: odSt },
    { label: "Over 90 days late", value: rs(k.b90p), sub: k.max_days ? `oldest ${nf(k.max_days)} days late` : "none", st: oldSt },
    { label: "Days sales outstanding", value: dso === null ? "–" : nf(dso) + " days", sub: `target ${T.dso_target} days`, st: dso === null ? undefined : dsoSt },
    { label: "Collected this month", value: rs(k.collected_mtd) },
  ];
  let html = tiles(tl) + ageing(k);
  html += mini("Customers to follow up (most overdue first)", (k.top || []).filter((x: any) => x.overdue > 0).map((x: any) => [x.party, `${rs(x.overdue)} overdue · ${nf(x.days)} days late · total ${rs(x.total)}`]));
  const mgmt: string[] = [], team: Section["team"] = [], good: string[] = [];
  const worstP = (k.top || []).filter((x: any) => x.overdue > 0).slice(0, 3).map((x: any) => x.party);
  if (k.overdue > 0 && odSt !== "ok") { mgmt.push(`${rs(k.overdue)} (${nf(od)}%) of the receivable is overdue${k.b90p > 0 ? `, ${rs(k.b90p)} of it more than 90 days` : ""}${worstP.length ? `. Main: ${worstP.join(", ")}` : ""}. Management call to these customers may be needed.`); team.push({ who: "Accounts and sales", text: `Call ${worstP.length ? worstP.join(", ") : "the overdue customers"} for payment dates; escalate bills older than 90 days; consider holding fresh supply to accounts that stay unpaid.` }); } else if (k.total > 0) good.push(`Receivables are healthy: ${nf(od, 1)}% overdue.`);
  if (dso !== null && dsoSt !== "ok") mgmt.push(`Money is coming in after ${nf(dso)} days on average against a target of ${T.dso_target} days.`);
  if (k.no_due_date > 0) team.push({ who: "Accounts", text: `${nf(k.no_due_date)} bill${k.no_due_date === 1 ? " has" : "s have"} no due date, so ageing is understated. Enter the credit days.` });
  return { key: "receivables", title: "Receivables (money to collect)", std: STD + " · ISO 9001 §8.2.4 customer payment terms", st, tiles: tl, html, open: "fin", mgmt, team, good };
}

function payables(k: K, T: Required<Pick<FinTargets, "overdue_pct_target">>): Section {
  const od = share(k.overdue, k.total);
  const odSt: St = lowerBetter(od, T.overdue_pct_target, 25);
  const oldSt: St = k.b90p > 0 ? "act" : k.b60 > 0 ? "watch" : "ok";
  const st = worst(odSt, oldSt);
  const tl = [
    { label: "Payable (we owe suppliers)", value: rs(k.total), sub: `${nf(k.bills)} bills` },
    { label: "Overdue to suppliers", value: rs(k.overdue), sub: `${nf(od, 1)}% of payable`, st: odSt },
    { label: "Due in next 7 days", value: rs(k.due_7), sub: "cash to arrange" },
    { label: "Paid this month", value: rs(k.paid_mtd), sub: k.max_days ? `oldest overdue ${nf(k.max_days)} days` : undefined, st: oldSt },
  ];
  let html = tiles(tl) + ageing(k);
  html += mini("Suppliers (most overdue first)", (k.top || []).map((x: any) => [x.party, x.overdue > 0 ? `${rs(x.overdue)} overdue · ${nf(x.days)} days · total ${rs(x.total)}` : `total ${rs(x.total)} · nothing overdue`]));
  const mgmt: string[] = [], team: Section["team"] = [], good: string[] = [];
  const names = (k.top || []).filter((x: any) => x.overdue > 0).slice(0, 3).map((x: any) => x.party);
  if (k.overdue > 0 && odSt !== "ok") { mgmt.push(`${rs(k.overdue)} is overdue to suppliers${names.length ? ` (${names.join(", ")})` : ""}. Late payment can stop material supply.`); team.push({ who: "Accounts", text: "Pay overdue bills of critical raw material and tooling suppliers first; agree dates with the others." }); } else if (k.total > 0) good.push("Supplier payments are within due dates.");
  if (k.due_7 > 0) team.push({ who: "Accounts", text: `Arrange ${rs(k.due_7)} that falls due in the next 7 days.` });
  if (k.no_due_date > 0) team.push({ who: "Accounts", text: `${nf(k.no_due_date)} supplier bill${k.no_due_date === 1 ? " has" : "s have"} no due date. Enter the credit days.` });
  return { key: "payables", title: "Payables (money to pay)", std: STD + " · IATF 16949 §8.4.2 supplier relationship", st, tiles: tl, html, open: "fin", mgmt, team, good };
}

function expenses(k: K, T: FinTargets, salesMtd: number | null): Section {
  const elapsed = (100 * k.day) / k.days_in_month;
  const heads = (k.heads || []) as { head: string; spent: number; budget: number | null; prev: number }[];
  const headSt = (h: { spent: number; budget: number | null }): St | undefined => (h.budget && h.budget > 0 ? (h.spent >= h.budget ? "act" : (100 * h.spent) / h.budget >= elapsed + 10 ? "watch" : "ok") : undefined);
  const over = heads.filter((h) => headSt(h) === "act"), fast = heads.filter((h) => headSt(h) === "watch");
  const budSt: St = over.length ? "act" : fast.length ? "watch" : "ok";
  const sp = salesMtd && salesMtd > 0 ? salesMtd : null;
  const expPct = sp ? (100 * k.total) / sp : null, matPct = sp && k.material !== null ? (100 * k.material) / sp : null;
  const exT = num(T.expense_pct_target), maT = num(T.material_pct_target);
  const expSt: St | undefined = expPct !== null && exT !== null ? lowerBetter(expPct, exT, 3) : undefined;
  const matSt: St | undefined = matPct !== null && maT !== null ? lowerBetter(matPct, maT, 3) : undefined;
  const st = worst(budSt, expSt ?? "ok", matSt ?? "ok");
  const costPct = sp ? (100 * (k.total + (k.material || 0))) / sp : null;
  const margin = sp ? sp - k.total - (k.material || 0) : null;
  const tl = [
    { label: "Expenses this month", value: rs(k.total), sub: k.budget_total ? `budget ${rs(k.budget_total)} · ${nf((100 * k.total) / k.budget_total)}% used, ${nf(elapsed)}% of month gone` : `last month ${rs(k.prev_total)}`, st: k.budget_total ? budSt : undefined },
    { label: "Expenses as % of sales", value: expPct === null ? "–" : nf(expPct, 1) + "%", sub: exT !== null ? `target ${exT}%` : "no target set", st: expSt },
    { label: "Raw material as % of sales", value: matPct === null ? "–" : nf(matPct, 1) + "%", sub: k.material === null ? "no Raw Material Planning data" : `${rs(k.material)} received${maT !== null ? ` · target ${maT}%` : ""}`, st: matSt },
    { label: "Left after material and expenses", value: rs(margin), sub: costPct === null ? undefined : `${nf(100 - costPct, 1)}% of sales, after the costs tracked here` },
  ];
  let html = tiles(tl);
  const withB = heads.filter((h) => h.budget && h.budget > 0);
  if (withB.length) html += `<div style="font-size:12px;font-weight:700;color:#0b1c3a;margin:10px 0 3px">Spent against budget (${nf(elapsed)}% of the month is gone)</div>` + bars(withB.slice(0, 8).map((h) => ({ label: h.head.slice(0, 14), v: Math.min(100, (100 * h.spent) / (h.budget as number)), max: 100, st: headSt(h) as St, right: `${rs(h.spent)} / ${rs(h.budget)}` })));
  html += mini("No budget set", heads.filter((h) => !h.budget && h.spent > 0).slice(0, 6).map((h) => [h.head, `${rs(h.spent)} this month · last month ${rs(h.prev)}`]));
  const mgmt: string[] = [], team: Section["team"] = [], good: string[] = [];
  if (over.length) { mgmt.push(`Over budget already: ${over.slice(0, 3).map((h) => `${h.head} (${rs(h.spent)} of ${rs(h.budget)})`).join(", ")}.`); team.push({ who: "Department heads", text: `Explain and stop non-essential spend on ${over.slice(0, 3).map((h) => h.head).join(", ")}; approve any further spend only with management sign-off.` }); }
  if (fast.length) mgmt.push(`Spending faster than the month: ${fast.slice(0, 3).map((h) => h.head).join(", ")}.`);
  if (expSt && expSt !== "ok") mgmt.push(`Expenses are ${nf(expPct, 1)}% of sales against a target of ${exT}%.`);
  if (matSt && matSt !== "ok") mgmt.push(`Raw material is ${nf(matPct, 1)}% of sales against a target of ${maT}%. Check rates, scrap and the product mix.`);
  if (!over.length && !fast.length && heads.some((h) => h.budget)) good.push("Spending is within budget for every head.");
  if (!k.budget_total) team.push({ who: "Accounts", text: "Enter the monthly budget per expense head so overspend can be flagged." });
  return { key: "expenses", title: "Expenses and cost against sales", std: STD + " · ISO 9001 §9.1.1 monitoring and measurement", st, tiles: tl, html, open: "fin", mgmt, team, good };
}

function cash(k: K): Section {
  const net = k.receipts - k.payments;
  const st: St = net < 0 ? "watch" : "ok";
  const tl = [
    { label: "Received from customers", value: rs(k.receipts), sub: "this month" },
    { label: "Paid to suppliers", value: rs(k.payments), sub: "this month" },
    { label: "Net (received less paid)", value: rs(net), sub: net < 0 ? "paying more than collecting" : "collecting more than paying", st },
    { label: "Last entry", value: dmy(k.last_date) },
  ];
  const mgmt: string[] = [], team: Section["team"] = [], good: string[] = [];
  if (net < 0) { mgmt.push(`This month ${rs(k.payments)} has gone out against ${rs(k.receipts)} received; watch the cash balance and push collections.`); team.push({ who: "Accounts", text: "Plan payments against expected collections for the next 7 days." }); } else good.push(`Cash is positive this month (${rs(net)} more received than paid).`);
  return { key: "cash", title: "Cash movement", std: STD, st, tiles: tl, html: tiles(tl), open: "fin", mgmt, team, good };
}

export function buildFinance(inp: FinInput) {
  const T = { ...FIN_DEFAULTS, ...Object.fromEntries(Object.entries(inp.targets || {}).filter(([, v]) => v !== null && v !== undefined && String(v) !== "" && Number.isFinite(Number(v))).map(([k, v]) => [k, Number(v)])) } as FinTargets & typeof FIN_DEFAULTS;
  const today = inp.today || new Date(Date.now() + 5.5 * 3600_000).toISOString().slice(0, 10);
  const on = (k: FinKey) => inp.sections?.[k] !== false && inp.kpis[k];
  const kp = inp.kpis, S: Section[] = [];
  if (on("sales")) S.push(sales(kp.sales!, today));
  if (on("receivables")) S.push(receivables(kp.receivables!, T, kp.sales ? num(kp.sales.gross_90) : null));
  if (on("payables")) S.push(payables(kp.payables!, T));
  if (on("expenses")) S.push(expenses(kp.expenses!, T, kp.sales ? num(kp.sales.mtd) : null));
  if (on("cash")) S.push(cash(kp.cash!));
  const missing = FIN_KEYS.filter((k) => inp.sections?.[k] !== false && !kp[k]).map((m) => ({ sales: "Sales (Sales Invoicing has no issued invoice)", receivables: "Receivables (no outstanding bills loaded)", payables: "Payables (no outstanding bills loaded)", expenses: "Expenses (no expense or budget entered)", cash: "Cash movement (no receipt or payment entered)" }[m]));
  const r = compose({ S, slug: inp.slug, company: inp.company, today, test: inp.test, platformUrl: inp.platformUrl, refPrefix: "FIN", format: FORMAT, title: "Finance report", missing,
    mgmtTitle: "Top management: where to concentrate today", teamTitle: "Accounts and sales: what to do today", settingsPath: "Administration › Finance mail", openLabel: "Open the portal",
    allClear: "Nothing needs top management attention today. Money figures are within targets.", noTeam: "No open money items for the teams today." });
  const conf = `<div style="background:#0b1c3a;color:#fff;font-size:11px;letter-spacing:.06em;padding:5px 10px;margin:0 0 10px">CONFIDENTIAL · FOR TOP MANAGEMENT ONLY · amounts in rupees (₹ L = lakh, ₹ Cr = crore)</div>`;
  return { ...r, html: conf + r.html };
}
