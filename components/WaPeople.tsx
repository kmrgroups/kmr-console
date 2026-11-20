"use client";
import { useState } from "react";

/** Add / remove the people who get the evening WhatsApp report. Saved as "name, mobile" lines in a hidden field. */
export function WaPeople({ initial }: { initial: string }) {
  const parse = (s: string) => s.split(/[\n;]+/).map((x) => x.trim()).filter(Boolean).map((x) => { const i = x.indexOf(","); return { name: i < 0 ? x : x.slice(0, i).trim(), phone: i < 0 ? "" : x.slice(i + 1).trim() }; });
  const [rows, setRows] = useState(parse(initial));
  const [n, setN] = useState(""), [p, setP] = useState("");
  const norm = (v: string) => { const d = v.replace(/[^0-9]/g, ""); return d.length === 10 ? "91" + d : d; };
  const add = () => { if (!n.trim() || norm(p).length < 10) return; setRows([...rows, { name: n.trim(), phone: norm(p) }]); setN(""); setP(""); };
  return (
    <div className="stack" style={{ gap: 8 }}>
      <input type="hidden" name="people" value={rows.map((r) => `${r.name}, ${norm(r.phone)}`).join("\n")} />
      {rows.length === 0 && <p className="muted" style={{ margin: 0 }}>No extra people yet.</p>}
      {rows.map((r, i) => (
        <div key={i} className="row" style={{ alignItems: "center", gap: 8 }}>
          <input value={r.name} onChange={(e) => setRows(rows.map((x, j) => (j === i ? { ...x, name: e.target.value } : x)))} aria-label="Name" style={{ width: 180 }} />
          <input value={r.phone} onChange={(e) => setRows(rows.map((x, j) => (j === i ? { ...x, phone: e.target.value } : x)))} aria-label="Mobile number" inputMode="tel" style={{ width: 220 }} />
          <button type="button" className="danger" onClick={() => { if (confirm(`Delete ${r.name || "this person"}?`)) setRows(rows.filter((_, j) => j !== i)); }}>Delete</button>
        </div>))}
      <div className="row" style={{ gap: 8 }}>
        <input value={n} onChange={(e) => setN(e.target.value)} placeholder="Name" aria-label="Name" style={{ width: 180 }} />
        <input value={p} onChange={(e) => setP(e.target.value)} placeholder="Mobile (10 digits or with 91)" aria-label="Mobile number" inputMode="tel" style={{ width: 220 }} onKeyDown={(e) => { if (e.key === "Enter") { e.preventDefault(); add(); } }} />
        <button type="button" onClick={add}>Add person</button>
      </div>
      <p className="muted" style={{ margin: 0 }}>Change a name or number directly in its row. Add, edit or delete, then press Save. A 10-digit Indian number gets 91 added.</p>
    </div>);
}
