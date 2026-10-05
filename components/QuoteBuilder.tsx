"use client";
import { useMemo, useState, useTransition } from "react";
import { saveQuote } from "@/app/quote-actions";
import { BASIS, addDays, basisText, inWords, inr, lineAmount, totals, type Basis, type QuoteInput, type QuoteLine, type ScopeRow } from "@/lib/quote";
import { p } from "@/lib/base-path";

export type Customer = { id: string; name: string; legal_name: string | null; contact_name: string | null; contact_email: string | null; contact_phone: string | null; address: string | null; city: string | null; state: string | null; postal_code: string | null; tax_id: string | null };
export type Product = { code: string; name: string; seat_label: string; description: string | null; prices: { period: string; unit_amount: number; min_seats: number }[]; features: string[]; tagline: string | null };
export type Cost = { id: string; product_code: string | null; name: string; detail: string | null; basis: Basis; amount: number; default_qty: number; include_by_default: boolean; active: boolean };

const NUM = { inputMode: "decimal" as const, style: { width: "100%", textAlign: "right" as const } };

export function QuoteBuilder({ initial, customers, products, costs, defaults }: {
  initial?: QuoteInput & { number?: string | null };
  customers: Customer[]; products: Product[]; costs: Cost[];
  defaults: { includes: string; terms: string; validity: number; gst: number; today: string };
}) {
  const [q, setQ] = useState<QuoteInput>(() => initial ?? {
    to_name: "", subject: "", intro: "", scope: [], lines: [], includes: defaults.includes, terms: defaults.terms,
    discount_pct: 0, gst_rate: defaults.gst, quote_date: defaults.today, valid_until: addDays(defaults.today, defaults.validity), customer_id: null,
  });
  const [msg, setMsg] = useState<{ ok?: string; error?: string }>({});
  const [busy, start] = useTransition();
  const set = <K extends keyof QuoteInput>(k: K, v: QuoteInput[K]) => setQ((x) => ({ ...x, [k]: v }));
  const setLine = (i: number, patch: Partial<QuoteLine>) => setQ((x) => ({ ...x, lines: x.lines.map((l, k) => (k === i ? { ...l, ...patch } : l)) }));
  const setScope = (i: number, patch: Partial<ScopeRow>) => setQ((x) => ({ ...x, scope: x.scope.map((l, k) => (k === i ? { ...l, ...patch } : l)) }));
  const move = <T,>(arr: T[], i: number, d: number) => { const a = arr.slice(), j = i + d; if (j < 0 || j >= a.length) return a; [a[i], a[j]] = [a[j], a[i]]; return a; };
  const t = useMemo(() => totals(q), [q]);
  const seat = (code?: string | null) => products.find((x) => x.code === code)?.seat_label ?? "users";
  const quoted = new Set(q.lines.map((l) => l.product_code).filter(Boolean));

  function pickCustomer(id: string) {
    const c = customers.find((x) => x.id === id);
    if (!c) { set("customer_id", null); return; }
    setQ((x) => ({ ...x, customer_id: c.id, to_name: c.legal_name || c.name, to_attn: c.contact_name ?? "", to_email: c.contact_email ?? "", to_phone: c.contact_phone ?? "",
      to_address: [c.address, c.city, c.state && c.postal_code ? `${c.state} ${c.postal_code}` : c.state || c.postal_code].filter(Boolean).join(", "), to_gstin: c.tax_id ?? "" }));
  }

  /** add an app: its subscription line, its scope row and the costing items marked "auto" */
  function addApp(code: string, period: "month" | "year") {
    const pr = products.find((x) => x.code === code); if (!pr) return;
    const price = pr.prices.find((x) => x.period === period) ?? pr.prices[0];
    const sub: QuoteLine = { product_code: code, particulars: `${pr.name} — cloud subscription`, detail: pr.tagline ?? pr.description ?? "",
      basis: price?.period === "year" ? "per_user_year" : "per_user_month", qty: price?.min_seats ?? 1, rate: Number(price?.unit_amount ?? 0), months: 12 };
    setQ((x) => {
      const have = new Set(x.lines.map((l) => l.particulars));
      const extra = costs.filter((c) => c.active && c.include_by_default && (c.product_code === code || !c.product_code) && !have.has(c.name))
        .map<QuoteLine>((c) => ({ product_code: c.product_code, particulars: c.name, detail: c.detail ?? "", basis: c.basis, qty: Number(c.default_qty), rate: Number(c.amount), months: 12 }));
      const firstOneTime = x.lines.findIndex((l) => !l.basis.startsWith("per_user"));
      const lines = firstOneTime < 0 ? [...x.lines, sub, ...extra] : [...x.lines.slice(0, firstOneTime), sub, ...x.lines.slice(firstOneTime), ...extra];
      const scope = x.scope.some((s) => s.module === pr.name) ? x.scope
        : [...x.scope, { module: pr.name, capability: pr.features.length ? pr.features.join("; ") : pr.tagline ?? pr.description ?? "" }];
      const names = Array.from(new Set(lines.filter((l) => l.basis.startsWith("per_user")).map((l) => products.find((p0) => p0.code === l.product_code)?.name).filter(Boolean)));
      return { ...x, lines, scope,
        subject: x.subject && !x.subject.startsWith("KMR Apps —") ? x.subject : `KMR Apps — ${names.join(", ")} (cloud subscription, implementation and training)`,
        intro: x.intro || "We are pleased to submit our commercial quotation for KMR Apps — cloud software built by manufacturing people for manufacturers. The scope, the detailed costing and the commercial terms are given below." };
    });
  }
  function addCost(id: string) {
    const c = costs.find((x) => x.id === id); if (!c) return;
    setQ((x) => ({ ...x, lines: [...x.lines, { product_code: c.product_code, particulars: c.name, detail: c.detail ?? "", basis: c.basis, qty: Number(c.default_qty), rate: Number(c.amount), months: 12 }] }));
  }

  function save(openPdf: boolean) {
    setMsg({});
    start(async () => {
      const r = await saveQuote({ ...q, id: (initial as { id?: string } | undefined)?.id ?? q.id });
      if (r.error) { setMsg({ error: r.error }); return; }
      setQ((x) => ({ ...x, id: r.id }));
      if (openPdf && r.id) window.open(p(`/api/quotes/${r.id}/pdf`), "_blank", "noopener");
      if (!initial?.id && r.id) { window.location.href = p(`/quotes/${r.id}?saved=1`); return; }
      setMsg({ ok: `Saved as ${r.number}.` });
    });
  }

  return (
    <div className="qb">
      <style>{`.qb table input,.qb table select,.qb table textarea{padding:6px 8px;font-size:13px}.qb .tot{display:grid;grid-template-columns:1fr auto;gap:6px 18px;font-size:14px}.qb .tot b{text-align:right}
        .qb .grand{background:var(--brand,#0B2A6F);color:#fff;border-radius:10px;padding:12px 16px;display:flex;justify-content:space-between;align-items:center;margin-top:10px}
        .qb .grand b{font-size:20px}.qb .chips{display:flex;flex-wrap:wrap;gap:8px}.qb .chips button{border:1px solid var(--border);background:var(--surface);border-radius:999px;padding:6px 12px;font-size:13px;cursor:pointer}
        .qb .chips button.on{border-color:var(--ok);color:var(--ok)}.qb .sticky{position:sticky;top:12px}.qb .icon{border:0;background:none;cursor:pointer;color:var(--muted);padding:2px 4px}
        .qb-layout{display:grid;grid-template-columns:minmax(0,1fr) 320px;gap:16px;align-items:start}.qb-layout>*{min-width:0}
        .qb .side2{display:grid;grid-template-columns:minmax(0,1fr) minmax(0,1fr);gap:10px}
        .qb table input,.qb table select{min-width:64px}.qb table td:nth-child(2) input{min-width:180px}
        @media(max-width:1000px){.qb-layout{grid-template-columns:minmax(0,1fr)}.qb .sticky{position:static;order:-1}}
        @media(max-width:640px){.qb .grand b{font-size:18px}.qb .chips button{font-size:12.5px;padding:6px 10px}}`}</style>
      <div className="qb-layout">
        <div>
          <div className="card">
            <h2>To</h2>
            <div className="formgrid">
              <label className="field">Existing customer<select value={q.customer_id ?? ""} onChange={(e) => pickCustomer(e.target.value)}><option value="">— a new prospect (type below) —</option>{customers.map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}</select></label>
              <label className="field">Company name *<input value={q.to_name} onChange={(e) => set("to_name", e.target.value)} placeholder="ABC Engineering Pvt. Ltd." /></label>
              <label className="field">Attention<input value={q.to_attn ?? ""} onChange={(e) => set("to_attn", e.target.value)} placeholder="The Managing Director / Plant Head" /></label>
              <label className="field">GSTIN<input value={q.to_gstin ?? ""} maxLength={15} onChange={(e) => set("to_gstin", e.target.value.toUpperCase())} /></label>
              <label className="field full">Address<input value={q.to_address ?? ""} onChange={(e) => set("to_address", e.target.value)} /></label>
              <label className="field">Email<input value={q.to_email ?? ""} onChange={(e) => set("to_email", e.target.value)} /></label>
              <label className="field">Phone<input value={q.to_phone ?? ""} onChange={(e) => set("to_phone", e.target.value)} /></label>
            </div>
          </div>

          <div className="card">
            <h2>Apps &amp; costing</h2>
            <p className="muted" style={{ marginTop: -4 }}>Add an app: its subscription (from the price list), its scope and the costing items marked <b>auto</b> are filled in. Then change quantities, months or rates as needed.</p>
            <div className="chips">{products.map((pr) => {
              const m = pr.prices.find((x) => x.period === "month"), y = pr.prices.find((x) => x.period === "year");
              return <span key={pr.code} style={{ display: "inline-flex", gap: 4 }}>
                <button type="button" className={quoted.has(pr.code) ? "on" : ""} onClick={() => addApp(pr.code, "year")} title={y ? `${inr(y.unit_amount)} / ${pr.seat_label.replace(/s$/, "")} / year` : "No yearly price"}>{quoted.has(pr.code) ? "✓ " : "+ "}{pr.name}{y ? ` · ${inr(y.unit_amount)}/yr` : ""}</button>
                {m && <button type="button" onClick={() => addApp(pr.code, "month")} title="Monthly billing">monthly</button>}
              </span>;
            })}</div>
            <div className="row" style={{ marginTop: 12, gap: 8 }}>
              <select defaultValue="" onChange={(e) => { if (e.target.value) addCost(e.target.value); e.target.value = ""; }} style={{ maxWidth: 420 }}>
                <option value="">+ Add from the costing catalogue…</option>
                {costs.filter((c) => c.active).map((c) => <option key={c.id} value={c.id}>{c.name} — {inr(c.amount)} {BASIS[c.basis].label.toLowerCase()}{c.product_code ? ` (${products.find((x) => x.code === c.product_code)?.name ?? c.product_code})` : ""}</option>)}
              </select>
              <button type="button" className="btn secondary small" onClick={() => set("lines", [...q.lines, { particulars: "", detail: "", basis: "one_time", qty: 1, rate: 0, months: 12 }])}>+ Blank line</button>
            </div>
            <div className="tablewrap" style={{ marginTop: 12 }}><table>
              <thead><tr><th style={{ width: 28 }}>#</th><th>Particulars</th><th style={{ width: 150 }}>Basis</th><th style={{ width: 80 }}>Qty</th><th style={{ width: 80 }}>Months</th><th style={{ width: 110 }}>Rate ₹</th><th style={{ width: 120, textAlign: "right" }}>Amount ₹</th><th style={{ width: 70 }} /></tr></thead>
              <tbody>{q.lines.length ? q.lines.map((l, i) => (
                <tr key={i}>
                  <td>{i + 1}</td>
                  <td><input value={l.particulars} onChange={(e) => setLine(i, { particulars: e.target.value })} placeholder="What is supplied" style={{ width: "100%", fontWeight: 600 }} />
                    <input value={l.detail ?? ""} onChange={(e) => setLine(i, { detail: e.target.value })} placeholder="Detail line (optional)" style={{ width: "100%", marginTop: 4, fontSize: 12 }} /></td>
                  <td><select value={l.basis} onChange={(e) => setLine(i, { basis: e.target.value as Basis })} style={{ width: "100%" }}>{Object.entries(BASIS).map(([k, b]) => <option key={k} value={k}>{b.label}</option>)}</select>
                    <small className="muted">{basisText(l, seat(l.product_code))}</small></td>
                  <td><input {...NUM} value={l.qty} onChange={(e) => setLine(i, { qty: Number(e.target.value) || 0 })} /></td>
                  <td>{BASIS[l.basis].months ? <input {...NUM} value={l.months ?? 12} onChange={(e) => setLine(i, { months: Number(e.target.value) || 1 })} /> : <small className="muted">—</small>}</td>
                  <td><input {...NUM} value={l.rate} onChange={(e) => setLine(i, { rate: Number(e.target.value) || 0 })} /></td>
                  <td style={{ textAlign: "right", whiteSpace: "nowrap" }}><b>{inr(lineAmount(l), false)}</b></td>
                  <td style={{ whiteSpace: "nowrap" }}>
                    <button type="button" className="icon" title="Move up" onClick={() => set("lines", move(q.lines, i, -1))}>↑</button>
                    <button type="button" className="icon" title="Move down" onClick={() => set("lines", move(q.lines, i, 1))}>↓</button>
                    <button type="button" className="icon" title="Remove" style={{ color: "var(--danger)" }} onClick={() => set("lines", q.lines.filter((_, k) => k !== i))}>✕</button>
                  </td>
                </tr>)) : <tr><td colSpan={8} className="muted" style={{ textAlign: "center", padding: 16 }}>Add an app or a costing item above.</td></tr>}</tbody>
            </table></div>
          </div>

          <div className="card">
            <h2>Subject &amp; scope</h2>
            <div className="formgrid">
              <label className="field full">Subject *<input value={q.subject} onChange={(e) => set("subject", e.target.value)} /></label>
              <label className="field full">Opening paragraph<textarea rows={3} value={q.intro ?? ""} onChange={(e) => set("intro", e.target.value)} /></label>
            </div>
            <div className="tablewrap" style={{ marginTop: 8 }}><table>
              <thead><tr><th style={{ width: 28 }}>#</th><th style={{ width: "32%" }}>Module</th><th>Included capability</th><th style={{ width: 70 }} /></tr></thead>
              <tbody>{q.scope.map((s, i) => (
                <tr key={i}><td>{i + 1}</td>
                  <td><input value={s.module} onChange={(e) => setScope(i, { module: e.target.value })} style={{ width: "100%", fontWeight: 600 }} /></td>
                  <td><textarea rows={2} value={s.capability} onChange={(e) => setScope(i, { capability: e.target.value })} style={{ width: "100%" }} /></td>
                  <td style={{ whiteSpace: "nowrap" }}><button type="button" className="icon" onClick={() => set("scope", move(q.scope, i, -1))}>↑</button><button type="button" className="icon" onClick={() => set("scope", move(q.scope, i, 1))}>↓</button><button type="button" className="icon" style={{ color: "var(--danger)" }} onClick={() => set("scope", q.scope.filter((_, k) => k !== i))}>✕</button></td>
                </tr>))}</tbody>
            </table></div>
            <button type="button" className="btn secondary small" style={{ marginTop: 8 }} onClick={() => set("scope", [...q.scope, { module: "", capability: "" }])}>+ Scope row</button>
          </div>

          <div className="card">
            <h2>Includes &amp; terms</h2>
            <div className="formgrid">
              <label className="field full">The subscription includes — one per line<textarea rows={5} value={q.includes ?? ""} onChange={(e) => set("includes", e.target.value)} /></label>
              <label className="field full">Commercial terms &amp; conditions — one per line<textarea rows={9} value={q.terms ?? ""} onChange={(e) => set("terms", e.target.value)} /></label>
              <label className="field full">Internal note (not printed)<input value={q.notes ?? ""} onChange={(e) => set("notes", e.target.value)} /></label>
            </div>
          </div>
        </div>

        <div className="sticky">
          <div className="card">
            <h2>{initial?.number ?? "New quotation"}</h2>
            <div className="side2">
              <label className="field">Date<input type="date" value={q.quote_date} onChange={(e) => set("quote_date", e.target.value)} /></label>
              <label className="field">Valid until<input type="date" value={q.valid_until ?? ""} onChange={(e) => set("valid_until", e.target.value)} /></label>
              <label className="field">Discount %<input {...NUM} value={q.discount_pct} onChange={(e) => set("discount_pct", Number(e.target.value) || 0)} /></label>
              <label className="field">GST %<input {...NUM} value={q.gst_rate} onChange={(e) => set("gst_rate", Number(e.target.value) || 0)} /></label>
            </div>
            <div className="tot" style={{ marginTop: 12 }}>
              <span>Recurring (subscriptions)</span><b>{inr(q.lines.filter((l) => /per_(user_)?(month|year)/.test(l.basis)).reduce((a, l) => a + lineAmount(l), 0))}</b>
              <span>One-time &amp; services</span><b>{inr(q.lines.filter((l) => !/per_(user_)?(month|year)/.test(l.basis)).reduce((a, l) => a + lineAmount(l), 0))}</b>
              <span>Sub-total</span><b>{inr(t.subtotal)}</b>
              {t.discount > 0 && <><span>Discount ({q.discount_pct}%)</span><b style={{ color: "var(--danger)" }}>− {inr(t.discount)}</b></>}
              <span>GST @ {q.gst_rate}%</span><b>{inr(t.gst)}</b>
            </div>
            <div className="grand"><span>Grand total</span><b>{inr(t.total)}</b></div>
            <p className="muted" style={{ fontSize: 12, marginTop: 8 }}>{inWords(t.total)}</p>
            {msg.error && <div className="alert danger" style={{ marginTop: 10 }}>{msg.error}</div>}
            {msg.ok && <div className="alert ok" style={{ marginTop: 10 }}>{msg.ok}</div>}
            <div className="stack" style={{ marginTop: 12, gap: 8, display: "grid" }}>
              <button type="button" className="btn" disabled={busy} onClick={() => save(true)}>{busy ? "Saving…" : "Save & open PDF"}</button>
              <button type="button" className="btn secondary" disabled={busy} onClick={() => save(false)}>Save</button>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
