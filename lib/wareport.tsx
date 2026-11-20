import { ImageResponse } from "next/og";

export type WaKpis = {
  day: string; days: string[];
  parts: { buyer: string | null; part: string; name?: string | null; d: number[]; total: number; sched: number; bal: number; val: number }[];
  plan_val: number; actual_val: number;
  invoices: { no: string; buyer: string | null; total: number }[];
  month_invoiced: number;
  rm?: { mat: string; unit: string | null; bal: number | null; used: string | null; recd: number; prev: number | null; slug: boolean }[];
  wip?: { part: string; name: string | null; min: number | null; stages: { seq: number; qty: number; name: string }[] }[];
};

const inr = (n: number) => "₹ " + Math.round(n).toLocaleString("en-IN");
const q = (n: number) => Math.round(n).toLocaleString("en-IN");
const dmy = (s: string) => { const [y, m, d] = s.slice(0, 10).split("-"); return `${d}-${m}-${y}`; };
const C = { head: "#1f2937", line: "#9ca3af", sched: "#fde047", bal: "#ef4444", ok: "#16a34a", dday: "#86efac" };
const cell = (w: number | string, bg?: string, bold = false, color = "#111827") => ({ display: "flex", justifyContent: "center", alignItems: "center", width: w, padding: "5px 4px", borderRight: `1px solid ${C.line}`, background: bg ?? "#ffffff", fontWeight: bold ? 700 : 400, color, fontSize: 18 } as const);

/** One picture for one unit: sales value plan / done / pending, today's invoices and the dispatch status table (same columns as the sheet the team used to prepare by hand). */
export async function renderUnitReport(unit: string, k: WaKpis): Promise<Uint8Array> {
  const parts = k.parts, rows = parts.length, inv = k.invoices.slice(0, 14);
  const pend = Math.max(0, k.plan_val - k.actual_val), pct = k.plan_val > 0 ? Math.round((100 * k.actual_val) / k.plan_val) : 0;
  const tot = parts.reduce((a, p) => ({ d: a.d.map((x, i) => x + (p.d[i] || 0)), total: a.total + p.total, sched: a.sched + p.sched, bal: a.bal + p.bal }), { d: [0, 0, 0], total: 0, sched: 0, bal: 0 });
  const height = 150 + 120 + (inv.length ? 40 + inv.length * 30 + 40 : 60) + 60 + (rows + 3) * 34 + 55;
  const W = 1000;
  const el = (
    <div style={{ display: "flex", flexDirection: "column", width: W, height, background: "#ffffff", fontFamily: "sans-serif", padding: 20 }}>
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", background: "#0e7490", color: "#fff", padding: "12px 16px", fontSize: 26, fontWeight: 700 }}>
        <div style={{ display: "flex" }}>{unit} · Daily report</div><div style={{ display: "flex" }}>{dmy(k.day)}</div>
      </div>
      <div style={{ display: "flex", marginTop: 14, gap: 12 }}>
        {[["Sales value plan (month)", inr(k.plan_val), "#e0f2fe"], ["Done so far", inr(k.actual_val) + "  (" + pct + "%)", "#dcfce7"], ["Pending", inr(pend), "#fee2e2"]].map(([l, v, bg]) => (
          <div key={l} style={{ display: "flex", flexDirection: "column", flex: 1, background: bg, padding: "10px 14px", borderRadius: 8 }}>
            <div style={{ display: "flex", fontSize: 16, color: "#374151" }}>{l}</div><div style={{ display: "flex", fontSize: 26, fontWeight: 700 }}>{v}</div></div>))}
      </div>
      <div style={{ display: "flex", marginTop: 16, fontSize: 20, fontWeight: 700 }}>{`Invoices today: ${k.invoices.length}  ·  ${inr(k.invoices.reduce((a, i) => a + Number(i.total || 0), 0))}   (month invoiced ${inr(k.month_invoiced)})`}</div>
      {inv.length ? <div style={{ display: "flex", flexDirection: "column", marginTop: 6, border: `1px solid ${C.line}` }}>
        {inv.map((i) => (<div key={i.no} style={{ display: "flex", borderBottom: `1px solid ${C.line}`, fontSize: 18, padding: "4px 8px" }}>
          <div style={{ display: "flex", width: 190 }}>{i.no}</div><div style={{ display: "flex", flex: 1 }}>{(i.buyer || "").slice(0, 46)}</div><div style={{ display: "flex", width: 160, justifyContent: "flex-end" }}>{inr(Number(i.total))}</div></div>))}
        {k.invoices.length > inv.length ? <div style={{ display: "flex", fontSize: 16, padding: "4px 8px" }}>{`… and ${k.invoices.length - inv.length} more`}</div> : null}
      </div> : <div style={{ display: "flex", fontSize: 18, marginTop: 6, color: "#6b7280" }}>No invoice issued today.</div>}
      <div style={{ display: "flex", marginTop: 18, background: "#67e8f9", padding: "8px 12px", fontSize: 22, fontWeight: 700 }}>{`Dispatch status — month of ${dmy(k.day).slice(3)}`}</div>
      <div style={{ display: "flex", flexDirection: "column", border: `1px solid ${C.line}`, borderBottom: "none" }}>
        <div style={{ display: "flex", borderBottom: `1px solid ${C.line}` }}>
          <div style={cell(250, "#38bdf8", true)}>Part No</div>
          {k.days.map((d) => <div key={d} style={cell(120, C.dday, true)}>{dmy(d)}</div>)}
          <div style={cell(130, "#d1d5db", true)}>Total dispatch</div><div style={cell(120, C.sched, true)}>Schedule</div><div style={cell(130, C.bal, true, "#fff")}>Balance</div>
        </div>
        {parts.map((p) => (
          <div key={p.part} style={{ display: "flex", borderBottom: `1px solid ${C.line}` }}>
            <div style={{ ...cell(250), justifyContent: "flex-start", paddingLeft: 8 }}>{p.part}</div>
            {p.d.map((x, i) => <div key={i} style={cell(120, undefined, x > 0)}>{q(x)}</div>)}
            <div style={cell(130, undefined, true)}>{q(p.total)}</div><div style={cell(120, "#fef9c3")}>{q(p.sched)}</div><div style={cell(130, undefined, true, p.bal < 0 ? "#b91c1c" : "#111827")}>{q(p.bal)}</div>
          </div>))}
        <div style={{ display: "flex", background: C.ok, color: "#fff", borderBottom: `1px solid ${C.line}` }}>
          <div style={cell(250, C.ok, true, "#fff")}>Total Qty</div>{tot.d.map((x, i) => <div key={i} style={cell(120, C.ok, true, "#fff")}>{q(x)}</div>)}
          <div style={cell(130, C.ok, true, "#fff")}>{q(tot.total)}</div><div style={cell(120, C.ok, true, "#fff")}>{q(tot.sched)}</div><div style={cell(130, C.ok, true, "#fff")}>{q(tot.bal)}</div>
        </div>
      </div>
      <div style={{ display: "flex", marginTop: 8, fontSize: 14, color: "#6b7280" }}>Auto-generated by KMR Console · Balance = schedule − total dispatch (negative = dispatched more than scheduled)</div>
    </div>);
  const res = new ImageResponse(el, { width: W + 0, height });
  return new Uint8Array(await res.arrayBuffer());
}

type Col = { h: string; w: number; bg?: string; color?: string };
type Cell = { v: string; bg?: string; bold?: boolean; color?: string; left?: boolean };
const GREY = "#d1d5db";

/** Generic sheet picture: coloured title bar, coloured column headings, rows, optional coloured total row. */
async function sheet(title: string, sub: string, titleBg: string, cols: Col[], rows: Cell[][], total?: Cell[]): Promise<Uint8Array> {
  const W = Math.max(760, cols.reduce((a, c) => a + c.w, 0) + 42), n = rows.length + (total ? 1 : 0);
  const height = 24 + 56 + 64 + n * 36 + 50;
  const row = (cells: Cell[], k: string | number) => (
    <div key={k} style={{ display: "flex", borderBottom: `1px solid ${C.line}` }}>
      {cells.map((c, i) => <div key={i} style={{ ...cell(cols[i].w, c.bg, c.bold, c.color), ...(c.left ? { justifyContent: "flex-start", paddingLeft: 8 } : {}) }}>{c.v}</div>)}
    </div>);
  const el = (
    <div style={{ display: "flex", flexDirection: "column", width: W, height, background: "#ffffff", fontFamily: "sans-serif", padding: 20 }}>
      <div style={{ display: "flex", justifyContent: "space-between", background: titleBg, padding: "10px 14px", fontSize: 24, fontWeight: 700 }}><div style={{ display: "flex" }}>{title}</div><div style={{ display: "flex" }}>{sub}</div></div>
      <div style={{ display: "flex", flexDirection: "column", marginTop: 8, border: `1px solid ${C.line}`, borderBottom: "none" }}>
        <div style={{ display: "flex", borderBottom: `1px solid ${C.line}` }}>{cols.map((c, i) => <div key={i} style={cell(c.w, c.bg ?? "#e5e7eb", true, c.color ?? "#111827")}>{c.h}</div>)}</div>
        {rows.map((r, i) => row(r, i))}
        {total ? row(total, "t") : null}
      </div>
      <div style={{ display: "flex", marginTop: 8, fontSize: 14, color: "#6b7280" }}>Auto-generated by KMR Console</div>
    </div>);
  return new Uint8Array(await new ImageResponse(el, { width: W, height }).arrayBuffer());
}

/** Customer-wise schedule: parts grouped under each customer, same columns as the dispatch sheet. */
export async function renderCustomerSchedule(unit: string, k: WaKpis): Promise<Uint8Array | null> {
  if (!k.parts.length) return null;
  const cols: Col[] = [{ h: "Customer", w: 170, bg: GREY }, { h: "Part No / Name", w: 300, bg: "#38bdf8" }, ...k.days.map((d) => ({ h: dmy(d), w: 100, bg: C.dday })), { h: "Total Qty Dispatch", w: 140, bg: GREY }, { h: "Schedule Qty", w: 120, bg: C.sched }, { h: "Balance Qty", w: 120, bg: C.bal, color: "#fff" }];
  const rows: Cell[][] = []; let last = "";
  const by = [...k.parts].sort((a, b) => (a.buyer || "").localeCompare(b.buyer || ""));
  for (const p of by) {
    const b = (p.buyer || "—").slice(0, 18);
    rows.push([{ v: b === last ? "" : b, bg: GREY, bold: true }, { v: `${p.part}${p.name ? " " + p.name : ""}`.slice(0, 34), left: true }, ...p.d.map((x) => ({ v: q(x), bold: x > 0 })), { v: q(p.total), bold: true }, { v: q(p.sched), bg: "#fef9c3" }, { v: q(p.bal), bold: true, color: p.bal < 0 ? "#b91c1c" : "#111827" }]);
    last = b;
  }
  return sheet(`${unit} · Customer-wise schedule`, dmy(k.day), "#fdba74", cols, rows);
}

const issued = (m: NonNullable<WaKpis["rm"]>[number]) => (m.prev == null || m.bal == null ? "—" : q(Math.max(0, Number(m.prev) + Number(m.recd || 0) - Number(m.bal))));

/** Forging slug material: balance of previous day / received / issued / balance (pink date heading like the sheet). */
export async function renderSlug(unit: string, k: WaKpis): Promise<Uint8Array | null> {
  const list = (k.rm || []).filter((m) => m.slug); if (!list.length) return null;
  const cols: Col[] = [{ h: "Material for Forging Slug", w: 330, bg: "#f9a8d4" }, { h: "Balance prev. day", w: 160, bg: "#f9a8d4" }, { h: "Received", w: 130, bg: "#f9a8d4" }, { h: "Issued", w: 130, bg: "#f9a8d4" }, { h: "Balance", w: 130, bg: "#f9a8d4" }];
  const rows = list.map((m) => [{ v: m.mat, left: true }, { v: m.prev == null ? "—" : q(Number(m.prev)) }, { v: q(m.recd || 0) }, { v: issued(m) }, { v: m.bal == null ? "—" : q(Number(m.bal)), bold: true }]);
  return sheet(`${unit} · Material for forging slug`, dmy(k.day), "#f9a8d4", cols, rows);
}

/** Daily RM stock: material, used for part, received, issued, balance. */
export async function renderRm(unit: string, k: WaKpis): Promise<Uint8Array | null> {
  const list = (k.rm || []).filter((m) => !m.slug); if (!list.length) return null;
  const cols: Col[] = [{ h: "Material", w: 260, bg: "#fed7aa" }, { h: "Used for part", w: 280, bg: "#fed7aa" }, { h: "Recd", w: 110, bg: "#fed7aa" }, { h: "Issued", w: 110, bg: "#fed7aa" }, { h: "Balance", w: 130, bg: "#fed7aa" }];
  const rows = list.map((m) => [{ v: m.mat, left: true }, { v: (m.used || "").slice(0, 30), left: true }, { v: q(m.recd || 0) }, { v: issued(m) }, { v: m.bal == null ? "—" : `${q(Number(m.bal))} ${m.unit || ""}`.trim(), bold: true }]);
  return sheet(`${unit} · Daily RM stock`, dmy(k.day), "#fdba74", cols, rows);
}

/** Stage-wise stock in progress, one picture per part family (name before the first "-"). Stage columns come from the process route. */
export async function renderWip(unit: string, k: WaKpis): Promise<{ family: string; png: Uint8Array }[]> {
  const fam = new Map<string, NonNullable<WaKpis["wip"]>>();
  for (const w of k.wip || []) { const f = ((w.name || w.part).split("-")[0] || w.part).trim().toUpperCase().slice(0, 28); fam.set(f, [...(fam.get(f) || []), w]); }
  const out: { family: string; png: Uint8Array }[] = [];
  for (const [f, list] of fam) {
    const names: string[] = []; for (const w of list) for (const s of w.stages) if (!names.includes(s.name)) names.push(s.name);
    const cols: Col[] = [{ h: "Part No", w: 230, bg: "#38bdf8" }, { h: "MIN", w: 70, bg: GREY }, ...names.map((n) => ({ h: n.slice(0, 14), w: 110, bg: "#e5e7eb" })), { h: "TOTAL", w: 110, bg: "#ef4444", color: "#fff" }];
    const rows = list.map((w) => { const t = w.stages.reduce((a, s) => a + Number(s.qty), 0); return [{ v: w.part, left: true, bold: true }, { v: w.min == null ? "" : q(w.min) }, ...names.map((n) => { const s = w.stages.find((x) => x.name === n); return { v: s ? q(Number(s.qty)) : "" }; }), { v: q(t), bold: true, bg: "#fee2e2" }]; });
    out.push({ family: f, png: await sheet(`${unit} · ${f} — stage-wise stock`, dmy(k.day), "#86efac", cols, rows) });
  }
  return out;
}

/** Every picture of the evening report for one unit, in sending order. */
export async function renderAll(unit: string, k: WaKpis): Promise<{ title: string; png: Uint8Array }[]> {
  const out: { title: string; png: Uint8Array }[] = [{ title: "Sales value, invoices and dispatch status", png: await renderUnitReport(unit, k) }];
  const add = (t: string, p: Uint8Array | null) => { if (p) out.push({ title: t, png: p }); };
  add("Customer-wise schedule", await renderCustomerSchedule(unit, k));
  add("Material for forging slug", await renderSlug(unit, k));
  add("Daily RM stock", await renderRm(unit, k));
  for (const w of await renderWip(unit, k)) out.push({ title: `${w.family} stage-wise stock`, png: w.png });
  return out;
}
