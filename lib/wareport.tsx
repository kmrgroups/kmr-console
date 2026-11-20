import { ImageResponse } from "next/og";

export type WaKpis = {
  day: string; days: string[];
  parts: { buyer: string | null; part: string; d: number[]; total: number; sched: number; bal: number; val: number }[];
  plan_val: number; actual_val: number;
  invoices: { no: string; buyer: string | null; total: number }[];
  month_invoiced: number;
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
