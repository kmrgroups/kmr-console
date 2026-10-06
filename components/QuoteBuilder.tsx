"use client";
import { useEffect, useMemo, useState, useTransition } from "react";
import { saveQuote } from "@/app/quote-actions";
import { BASIS, addDays, basisText, inWords, inr, lineAmount, totals, type Basis, type QuoteInput, type QuoteLine, type ScopeRow } from "@/lib/quote";
import { p } from "@/lib/base-path";
import { featurePrice, type Feature } from "@/lib/features";

export type Customer = { id: string; name: string; legal_name: string | null; contact_name: string | null; contact_email: string | null; contact_phone: string | null; address: string | null; city: string | null; state: string | null; postal_code: string | null; tax_id: string | null };
export type Product = { code: string; name: string; seat_label: string; description: string | null; prices: { period: string; unit_amount: number; min_seats: number }[]; features: string[]; featureList: Feature[]; tagline: string | null };
export type Lead = { id: string; name: string; company: string | null; email: string | null; phone: string | null; country: string | null; business: string; product_name: string | null; quantity: string | null; message: string | null; status: string; customer_id: string | null; created_at: string };
export type Cost = { id: string; product_code: string | null; name: string; detail: string | null; basis: Basis; amount: number; default_qty: number; include_by_default: boolean; active: boolean };

const NUM = { inputMode: "decimal" as const, style: { width: "100%", textAlign: "right" as const } };

export type Paper = { letterhead: string; seal: string | null; signature: string | null; company: string; signatory: string | null };

export function QuoteBuilder({ initial, customers, leads = [], startLead, products, costs, defaults, paper, status, children }: {
  initial?: QuoteInput & { number?: string | null };
  customers: Customer[]; leads?: Lead[]; startLead?: string | null; products: Product[]; costs: Cost[];
  paper: Paper; status?: string; children?: React.ReactNode;
  defaults: { includes: string; terms: string; validity: number; gst: number; today: string };
}) {
  const [q, setQ] = useState<QuoteInput>(() => initial ?? {
    to_name: "", subject: "", intro: "", scope: [], lines: [], includes: defaults.includes, terms: defaults.terms,
    discount_pct: 0, gst_rate: defaults.gst, quote_date: defaults.today, valid_until: addDays(defaults.today, defaults.validity), customer_id: null,
  });
  const [msg, setMsg] = useState<{ ok?: string; error?: string }>({});
  const BL: Record<string, string> = { software: "Software", shop: "Shop", training: "Training", import_export: "Import & export", trading: "Trading", distribution: "Distribution", general: "General" };
  /** draft the quotation against a website enquiry: who it is for, what they asked about, and a reply opening */
  function pickLead(id: string) {
    const l = leads.find((x) => x.id === id);
    if (!l) { set("lead_id", null); return; }
    const c = l.customer_id ? customers.find((x) => x.id === l.customer_id) : undefined;
    const when = new Date(l.created_at).toLocaleDateString("en-IN", { day: "2-digit", month: "long", year: "numeric" });
    const about = l.product_name || BL[l.business] || "your requirement";
    setQ((x) => ({ ...x, lead_id: l.id,
      customer_id: c?.id ?? x.customer_id ?? null,
      to_name: c ? (c.legal_name || c.name) : (l.company || l.name),
      to_attn: l.company ? l.name : (c?.contact_name ?? ""),
      to_email: l.email ?? c?.contact_email ?? "", to_phone: l.phone ?? c?.contact_phone ?? "",
      to_address: c ? [c.address, c.city, c.state].filter(Boolean).join(", ") : (l.country && l.country !== "IN" ? l.country : x.to_address ?? ""),
      to_gstin: c?.tax_id ?? x.to_gstin ?? "",
      subject: x.subject || `Quotation for ${about}${l.quantity ? ` — ${l.quantity}` : ""}`,
      intro: `Thank you for your enquiry dated ${when} regarding ${about}${l.quantity ? ` (${l.quantity})` : ""}. We are pleased to submit our quotation below — the scope, the detailed costing and the commercial terms are given in this document.`,
      notes: x.notes || (l.message ? `Enquiry: ${l.message.slice(0, 400)}` : ""),
    }));
  }
  const leadNow = leads.find((x) => x.id === q.lead_id);
  useEffect(() => { if (startLead && !initial) pickLead(startLead); /* eslint-disable-next-line react-hooks/exhaustive-deps */ }, []);
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
  /* ---- feature picker: the price of an app is the sum of the features chosen ---- */
  const [pick, setPick] = useState<{ code: string; period: "month" | "year"; users: number; chosen: Set<string> } | null>(null);
  function openPicker(code: string, period: "month" | "year") {
    const pr = products.find((x) => x.code === code); if (!pr) return;
    if (!pr.featureList.length) { addApp(code, period); return; }          // before 0050: the flat per-user price
    const have = new Set(q.lines.filter((l) => l.product_code === code && l.feature_id).map((l) => l.feature_id as string));
    const existing = q.lines.find((l) => l.product_code === code && l.feature_id);
    const minSeats = (pr.prices.find((x) => x.period === period) ?? pr.prices[0])?.min_seats ?? 1;
    setPick({ code, period: existing?.basis === "per_user_year" ? "year" : existing?.basis === "per_user_month" ? "month" : period,
      users: existing ? Number(existing.qty) || minSeats : minSeats,
      chosen: have.size ? have : new Set(pr.featureList.map((f) => f.id)) });
  }
  function applyPicker() {
    if (!pick) return;
    const pr = products.find((x) => x.code === pick.code); if (!pr) return;
    const fs = pr.featureList.filter((f) => f.is_core || pick.chosen.has(f.id));
    const per = pick.period;
    const lines = fs.map<QuoteLine>((f) => ({ product_code: pr.code, feature_id: f.id, particulars: `${pr.name} — ${f.name}`, detail: f.detail ?? "",
      basis: per === "year" ? "per_user_year" : "per_user_month", qty: pick.users, rate: featurePrice(f, per), months: 12 }));
    const setup = fs.reduce((a, f) => a + (Number(f.setup_fee) || 0), 0);
    if (setup > 0) lines.push({ product_code: null, particulars: `${pr.name} — one-time set-up of the chosen features`, detail: "", basis: "one_time", qty: 1, rate: setup, months: 12 });
    setQ((x) => {
      // replace this app's earlier subscription lines (feature lines, its flat line and its set-up line), keep everything else
      const kept = x.lines.filter((l) => !((l.product_code === pr.code && (l.feature_id || l.basis.startsWith("per_user"))) || l.particulars === `${pr.name} — one-time set-up of the chosen features`));
      const at = Math.max(0, x.lines.findIndex((l) => l.product_code === pr.code && (l.feature_id || l.basis.startsWith("per_user"))));
      const firstOneTime = kept.findIndex((l) => !l.basis.startsWith("per_user"));
      const pos = x.lines.some((l) => l.product_code === pr.code && l.feature_id) ? Math.min(at, kept.length) : firstOneTime < 0 ? kept.length : firstOneTime;
      const have = new Set(kept.map((l) => l.particulars));
      const extra = x.lines.some((l) => l.product_code === pr.code && l.feature_id) ? [] : costs.filter((c) => c.active && c.include_by_default && (c.product_code === pr.code || !c.product_code) && !have.has(c.name))
        .map<QuoteLine>((c) => ({ product_code: c.product_code, particulars: c.name, detail: c.detail ?? "", basis: c.basis, qty: Number(c.default_qty), rate: Number(c.amount), months: 12 }));
      const out = [...kept.slice(0, pos), ...lines, ...kept.slice(pos), ...extra];
      const scopeText = fs.map((f) => f.name).join("; ");
      const scope = x.scope.some((s0) => s0.module === pr.name) ? x.scope.map((s0) => (s0.module === pr.name ? { ...s0, capability: scopeText } : s0)) : [...x.scope, { module: pr.name, capability: scopeText }];
      const names = Array.from(new Set(out.filter((l) => l.basis.startsWith("per_user")).map((l) => products.find((p0) => p0.code === l.product_code)?.name).filter(Boolean)));
      return { ...x, lines: out, scope,
        subject: x.subject && !x.subject.startsWith("KMR Apps —") ? x.subject : `KMR Apps — ${names.join(", ")} (cloud subscription, implementation and training)`,
        intro: x.intro || "We are pleased to submit our commercial quotation for KMR Apps — cloud software built by manufacturing people for manufacturers. The scope, the detailed costing and the commercial terms are given below." };
    });
    setPick(null);
  }
  function addCost(id: string) {
    const c = costs.find((x) => x.id === id); if (!c) return;
    setQ((x) => ({ ...x, lines: [...x.lines, { product_code: c.product_code, particulars: c.name, detail: c.detail ?? "", basis: c.basis, qty: Number(c.default_qty), rate: Number(c.amount), months: 12 }] }));
  }

  const [pdfBusy, setPdfBusy] = useState<"" | "view" | "download">("");
  async function pdf(download: boolean) {
    setMsg({});
    // open the tab inside the tap (phones block pop-ups opened after a wait), then fill it with the PDF
    const tab = download ? null : window.open("", "_blank");
    if (tab) tab.document.write("<p style='font:16px system-ui;padding:24px;color:#555'>Preparing the quotation PDF…</p>");
    setPdfBusy(download ? "download" : "view");
    try {
      const r = await fetch(p("/api/quotes/preview"), { method: "POST", headers: { "content-type": "application/json" },
        body: JSON.stringify({ ...q, number: initial?.number ?? null, status: status ?? "draft", download }) });
      if (!r.ok) throw new Error((await r.json().catch(() => ({}))).error || `Could not make the PDF (${r.status}).`);
      const url = URL.createObjectURL(await r.blob());
      if (download) {
        const a = document.createElement("a"); a.href = url;
        a.download = `Quotation_${String(initial?.number || "draft").replace(/[^\w-]+/g, "-")}_${(q.to_name || "").replace(/[^\w-]+/g, "-").slice(0, 40)}.pdf`;
        document.body.append(a); a.click(); a.remove();
      } else if (tab) tab.location.href = url; else window.location.href = url;
      setTimeout(() => URL.revokeObjectURL(url), 60_000);
    } catch (e) { tab?.close(); setMsg({ error: (e as Error).message }); }
    finally { setPdfBusy(""); }
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

  const dateLong = (d?: string | null) => d ? new Date(d + "T00:00:00Z").toLocaleDateString("en-IN", { day: "2-digit", month: "long", year: "numeric", timeZone: "UTC" }) : "—";
  const draft = !status || status === "draft";
  const recurring = q.lines.filter((l) => /per_(user_)?(month|year)/.test(l.basis)).reduce((a, l) => a + lineAmount(l), 0);

  return (
    <div className="qb invoice-layout">
      <style>{`
        .qdoc input,.qdoc textarea,.qdoc select{border:1px dashed transparent;background:transparent;border-radius:6px;padding:3px 6px;font:inherit;color:inherit;width:100%;min-width:0;box-shadow:none}
        .qdoc input:hover,.qdoc textarea:hover,.qdoc select:hover{border-color:#d8c08a}
        .qdoc input:focus,.qdoc textarea:focus,.qdoc select:focus{border-color:var(--kmr-gold,#C9A24B);background:#fffdf6;outline:none}
        .qdoc textarea{resize:vertical;line-height:1.5}
        .qdoc .qtitle{text-align:center;font-size:1.35rem;font-weight:800;letter-spacing:.08em;color:#0b1f45;margin:4px 0 2px}
        .qdoc .qtitle::after{content:"";display:block;width:56px;height:3px;background:#C9A24B;margin:6px auto 0;border-radius:2px}
        .qdoc .qref{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:8px;background:var(--surface-2,#f4f6fb);border:1px solid var(--border);border-radius:8px;padding:8px 10px;margin:14px 0}
        .qdoc .qref small{display:block;font-size:10px;font-weight:700;letter-spacing:.08em;color:var(--muted);text-transform:uppercase}
        .qdoc .qref b,.qdoc .qref input{font-weight:600;color:#0b1f45}
        .qdoc .qto{display:grid;grid-template-columns:minmax(0,1.3fr) minmax(0,1fr);gap:4px 16px}
        .qdoc .qsubject{display:flex;align-items:center;gap:8px;background:#0b1f45;color:#fff;border-left:4px solid #C9A24B;border-radius:4px;padding:6px 10px;margin:12px 0}
        .qdoc .qsubject input{color:#fff;font-weight:700}.qdoc .qsubject input::placeholder{color:#ffffff99}
        .qdoc h4{font-size:13px;font-weight:800;color:#0b1f45;margin:16px 0 6px;letter-spacing:.02em}
        .qdoc h4::after{content:"";display:block;width:30px;height:2px;background:#C9A24B;margin-top:4px}
        .qdoc .invoice-lines input,.qdoc .invoice-lines select,.qdoc .invoice-lines textarea{padding:2px 4px}
        .qdoc .qprice{min-width:820px}.qdoc .qprice select{min-width:128px}.qdoc .qprice td:nth-child(2){min-width:240px}
        .qdoc .qprice td{vertical-align:top}
        .qdoc .qdraft{width:max-content;margin:6px 0 -6px auto;border:3px solid var(--muted);color:var(--muted);border-radius:8px;padding:1px 12px;font-weight:800;letter-spacing:.18em;text-transform:uppercase;font-size:13px;transform:rotate(-6deg);opacity:.75}
        .qdoc .num input{text-align:right}
        .qdoc .rowtools{white-space:nowrap}.qdoc .rowtools button{border:0;background:none;cursor:pointer;color:var(--muted);padding:2px 3px}
        .qdoc .addrow{margin-top:6px}
        .qdoc .qgrand{background:#0b1f45;color:#fff}.qdoc .qgrand th{color:#C9A24B!important}.qdoc .qgrand td{color:#fff!important}
        .qpanel .chips{display:flex;flex-wrap:wrap;gap:6px}.qpanel .chips button{border:1px solid var(--border);background:var(--surface);border-radius:999px;padding:5px 10px;font-size:12.5px;cursor:pointer}
        .qpanel .chips button.on{border-color:var(--ok);color:var(--ok)}
        .qpanel .tot{display:grid;grid-template-columns:1fr auto;gap:4px 12px;font-size:13.5px}.qpanel .tot b{text-align:right}
        .qpanel .grand{background:#0b1f45;color:#fff;border-radius:10px;padding:10px 14px;display:flex;justify-content:space-between;align-items:center;margin-top:8px}.qpanel .grand b{font-size:18px}
        @media(max-width:1100px){.qb.invoice-layout .qpanel{order:-1}}
        @media(max-width:700px){.qdoc .qref{grid-template-columns:1fr 1fr}.qdoc .qto{grid-template-columns:1fr}.qdoc .invoice-lines .hide-sm{display:none}}
      `}</style>

      {/* ---------------- the quotation, edited directly on the letterhead ---------------- */}
      <article className="invoice on-letterhead qdoc">
        <div className="lh-band lh-top" style={{ backgroundImage: `url("${paper.letterhead}")` }} role="img" aria-label={`${paper.company} letterhead`} />
        <div className="qtitle">QUOTATION</div>
        {draft && <div className="qdraft">Draft</div>}
        <div className="qref">
          <div><small>Quotation no.</small><b className="mono">{initial?.number ?? "— (given on save)"}</b></div>
          <div><small>Date</small><input type="date" value={q.quote_date} onChange={(e) => set("quote_date", e.target.value)} aria-label="Quotation date" /></div>
          <div><small>Valid until</small><input type="date" value={q.valid_until ?? ""} onChange={(e) => set("valid_until", e.target.value)} aria-label="Valid until" /></div>
          <div><small>Currency</small><b>INR (₹)</b></div>
        </div>

        <div className="invoice-label">To</div>
        <div className="qto">
          <input value={q.to_name} onChange={(e) => set("to_name", e.target.value)} placeholder="M/s. Company name *" style={{ fontWeight: 700, fontSize: 15, color: "#0b1f45" }} aria-label="Company name" />
          <input value={q.to_gstin ?? ""} maxLength={15} onChange={(e) => set("to_gstin", e.target.value.toUpperCase())} placeholder="GSTIN" aria-label="GSTIN" className="mono" />
          <input value={q.to_attn ?? ""} onChange={(e) => set("to_attn", e.target.value)} placeholder="Attn: name / designation" aria-label="Attention" />
          <input value={q.to_email ?? ""} onChange={(e) => set("to_email", e.target.value)} placeholder="Email" aria-label="Email" />
          <input value={q.to_address ?? ""} onChange={(e) => set("to_address", e.target.value)} placeholder="Address" aria-label="Address" />
          <input value={q.to_phone ?? ""} onChange={(e) => set("to_phone", e.target.value)} placeholder="Phone" aria-label="Phone" />
        </div>

        <div className="qsubject"><b style={{ whiteSpace: "nowrap" }}>SUBJECT:</b><input value={q.subject} onChange={(e) => set("subject", e.target.value)} placeholder="What this quotation is for *" aria-label="Subject" /></div>
        <p style={{ margin: "4px 0" }}>Dear Sir / Madam,</p>
        <textarea rows={3} value={q.intro ?? ""} onChange={(e) => set("intro", e.target.value)} placeholder="Opening paragraph" aria-label="Opening paragraph" />

        <h4>1. SCOPE OF SUPPLY</h4>
        <div className="invoice-scroll"><table className="invoice-lines">
          <thead><tr><th style={{ width: 28 }}>#</th><th style={{ width: "32%" }}>Module</th><th>Included capability</th><th style={{ width: 64 }} /></tr></thead>
          <tbody>{q.scope.length ? q.scope.map((s0, i) => (
            <tr key={i}><td>{i + 1}</td>
              <td><input value={s0.module} onChange={(e) => setScope(i, { module: e.target.value })} style={{ fontWeight: 600 }} aria-label="Module" /></td>
              <td><textarea rows={2} value={s0.capability} onChange={(e) => setScope(i, { capability: e.target.value })} aria-label="Included capability" /></td>
              <td className="rowtools"><button type="button" title="Up" onClick={() => set("scope", move(q.scope, i, -1))}>↑</button><button type="button" title="Down" onClick={() => set("scope", move(q.scope, i, 1))}>↓</button><button type="button" title="Remove" style={{ color: "var(--danger)" }} onClick={() => set("scope", q.scope.filter((_, k) => k !== i))}>✕</button></td>
            </tr>)) : <tr><td colSpan={4} className="muted" style={{ textAlign: "center" }}>Add an app from the panel — its scope fills in here.</td></tr>}</tbody>
        </table></div>
        <button type="button" className="btn ghost small addrow" onClick={() => set("scope", [...q.scope, { module: "", capability: "" }])}>+ Scope row</button>

        <h4>2. COMMERCIAL PROPOSAL</h4>
        <div className="invoice-scroll"><table className="invoice-lines qprice">
          <thead><tr><th style={{ width: 28 }}>#</th><th>Particulars</th><th style={{ width: 150 }}>Basis</th><th className="num" style={{ width: 70 }}>Qty</th><th className="num hide-sm" style={{ width: 66 }}>Months</th><th className="num" style={{ width: 100 }}>Rate ₹</th><th className="num" style={{ width: 108 }}>Amount ₹</th><th style={{ width: 64 }} /></tr></thead>
          <tbody>{q.lines.length ? q.lines.map((l, i) => (
            <tr key={i}>
              <td>{i + 1}</td>
              <td><input value={l.particulars} onChange={(e) => setLine(i, { particulars: e.target.value })} placeholder="What is supplied" style={{ fontWeight: 600, minWidth: 160 }} aria-label="Particulars" />
                <input value={l.detail ?? ""} onChange={(e) => setLine(i, { detail: e.target.value })} placeholder="detail line (optional)" style={{ fontSize: 12, color: "var(--muted)" }} aria-label="Detail" /></td>
              <td><select value={l.basis} onChange={(e) => setLine(i, { basis: e.target.value as Basis })} aria-label="Basis">{Object.entries(BASIS).map(([k, b]) => <option key={k} value={k}>{b.label}</option>)}</select>
                <small className="muted">{basisText(l, seat(l.product_code))}</small></td>
              <td className="num"><input {...NUM} value={l.qty} onChange={(e) => setLine(i, { qty: Number(e.target.value) || 0 })} aria-label="Quantity" /></td>
              <td className="num hide-sm">{BASIS[l.basis].months ? <input {...NUM} value={l.months ?? 12} onChange={(e) => setLine(i, { months: Number(e.target.value) || 1 })} aria-label="Months" /> : <span className="muted">—</span>}</td>
              <td className="num"><input {...NUM} value={l.rate} onChange={(e) => setLine(i, { rate: Number(e.target.value) || 0 })} aria-label="Rate" /></td>
              <td className="num"><b>{inr(lineAmount(l), false)}</b></td>
              <td className="rowtools"><button type="button" title="Up" onClick={() => set("lines", move(q.lines, i, -1))}>↑</button><button type="button" title="Down" onClick={() => set("lines", move(q.lines, i, 1))}>↓</button><button type="button" title="Remove" style={{ color: "var(--danger)" }} onClick={() => set("lines", q.lines.filter((_, k) => k !== i))}>✕</button></td>
            </tr>)) : <tr><td colSpan={8} className="muted" style={{ textAlign: "center", padding: 14 }}>Add an app or a costing item from the panel.</td></tr>}</tbody>
        </table></div>
        <button type="button" className="btn ghost small addrow" onClick={() => set("lines", [...q.lines, { particulars: "", detail: "", basis: "one_time", qty: 1, rate: 0, months: 12 }])}>+ Blank line</button>

        <section className="invoice-bottom">
          <div className="invoice-words"><div className="invoice-label">Amount in words</div><div>{inWords(t.total)}</div></div>
          <table className="invoice-totals"><tbody>
            <tr><th>Sub-total</th><td>{inr(t.subtotal)}</td></tr>
            {t.discount > 0 && <><tr><th>Less: discount @ {q.discount_pct}%</th><td>− {inr(t.discount)}</td></tr><tr><th>Total before GST</th><td>{inr(t.taxable)}</td></tr></>}
            <tr><th>GST @ {q.gst_rate}%</th><td>{inr(t.gst)}</td></tr>
            <tr className="grand qgrand"><th>GRAND TOTAL</th><td>{inr(t.total)}</td></tr>
          </tbody></table>
        </section>

        <h4>3. THE SUBSCRIPTION INCLUDES <small className="muted" style={{ fontWeight: 400 }}>— one per line</small></h4>
        <textarea rows={5} value={q.includes ?? ""} onChange={(e) => set("includes", e.target.value)} aria-label="The subscription includes" />
        <h4>4. COMMERCIAL TERMS &amp; CONDITIONS <small className="muted" style={{ fontWeight: 400 }}>— one per line</small></h4>
        <textarea rows={8} value={q.terms ?? ""} onChange={(e) => set("terms", e.target.value)} aria-label="Terms and conditions" />

        <footer className="invoice-foot">
          <span className="invoice-foot-note">Customer acceptance is printed beside our signatory on the PDF.</span>
          <div className="invoice-sign-wrap">
            {paper.seal && <img src={paper.seal} alt="Company seal" className="invoice-seal" />}
            <div className="invoice-sign">
              <div>For {paper.company}</div>
              <div className="invoice-sig-area">{paper.signature && <img src={paper.signature} alt="Signature" className="invoice-signature" />}</div>
              {paper.signatory && <div className="invoice-sign-name">{paper.signatory}</div>}
              <div className="muted" style={{ fontSize: 11.5 }}>Authorised Signatory</div>
            </div>
          </div>
        </footer>
        <div className="lh-band lh-bottom" style={{ backgroundImage: `url("${paper.letterhead}")` }} aria-hidden="true" />
      </article>

      {/* ---------------- the panel, like the draft-invoice panel ---------------- */}
      <aside className="stack qpanel">
        <div className="card">
          <h2>{initial?.number ?? "New quotation"}</h2>
          <label className="field">Against an enquiry
            <select value={q.lead_id ?? ""} onChange={(e) => pickLead(e.target.value)}>
              <option value="">— none: draft manually —</option>
              {leads.map((l) => <option key={l.id} value={l.id}>{new Date(l.created_at).toLocaleDateString("en-IN", { day: "2-digit", month: "short" })} · {l.company || l.name} · {l.product_name || BL[l.business] || l.business}{l.status === "quoted" ? " (quoted)" : ""}</option>)}
            </select>
            {leadNow?.message && <span className="help" style={{ whiteSpace: "pre-line" }}>“{leadNow.message.slice(0, 220)}{leadNow.message.length > 220 ? "…" : ""}”</span>}
          </label>
          <label className="field" style={{ marginTop: 8 }}>Existing customer
            <select value={q.customer_id ?? ""} onChange={(e) => pickCustomer(e.target.value)}><option value="">— a new prospect —</option>{customers.map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}</select>
          </label>
        </div>

        <div className="card">
          <h2>Add apps &amp; costing</h2>
          <p className="muted" style={{ fontSize: 12.5, marginTop: -4 }}>Pick an app, then tick its features — the price is the sum of the features. Core features are always included. “monthly” bills per month instead of per year.</p>
          <div className="chips">{products.map((pr) => {
            const m = pr.prices.find((x) => x.period === "month"), y = pr.prices.find((x) => x.period === "year");
            return <span key={pr.code} style={{ display: "inline-flex", gap: 4 }}>
              <button type="button" className={quoted.has(pr.code) ? "on" : ""} onClick={() => openPicker(pr.code, "year")}>{quoted.has(pr.code) ? "✓ " : "+ "}{pr.name}{y ? ` · from ${inr(pr.featureList.length ? pr.featureList.filter((f) => f.is_core).reduce((a, f) => a + Number(f.price_year), 0) : y.unit_amount)}/yr` : ""}</button>
              {m && <button type="button" onClick={() => openPicker(pr.code, "month")}>monthly</button>}
            </span>;
          })}</div>
          {pick && (() => {
            const pr = products.find((x) => x.code === pick.code)!;
            const per = pick.period, sel = pr.featureList.filter((f) => f.is_core || pick.chosen.has(f.id));
            const each = sel.reduce((a, f) => a + featurePrice(f, per), 0), setup = sel.reduce((a, f) => a + (Number(f.setup_fee) || 0), 0);
            return <div style={{ marginTop: 12, border: "1px solid var(--kmr-gold,#C9A24B)", borderRadius: 10, padding: 12 }}>
              <b>{pr.name} — choose features</b>
              <div className="formgrid" style={{ gridTemplateColumns: "minmax(0,1fr) minmax(0,1fr)", marginTop: 8 }}>
                <label className="field">Billing<select value={per} onChange={(e) => setPick({ ...pick, period: e.target.value as "month" | "year" })}><option value="year">Yearly</option><option value="month">Monthly</option></select></label>
                <label className="field">{pr.seat_label}<input {...NUM} value={pick.users} onChange={(e) => setPick({ ...pick, users: Math.max(1, Number(e.target.value) || 1) })} /></label>
              </div>
              <div style={{ display: "grid", gap: 6, margin: "8px 0" }}>{pr.featureList.map((f) => (
                <label key={f.id} style={{ display: "flex", gap: 8, alignItems: "flex-start", fontSize: 13 }}>
                  <input type="checkbox" checked={f.is_core || pick.chosen.has(f.id)} disabled={f.is_core}
                    onChange={(e) => { const c = new Set(pick.chosen); if (e.target.checked) c.add(f.id); else c.delete(f.id); setPick({ ...pick, chosen: c }); }} />
                  <span style={{ flex: 1 }}>{f.name}{f.is_core && <small className="muted"> · core</small>}</span>
                  <span style={{ whiteSpace: "nowrap" }}>{inr(featurePrice(f, per))}</span>
                </label>))}</div>
              <div className="tot"><span>Per {pr.seat_label.replace(/s$/, "")} / {per}</span><b>{inr(each)}</b>
                <span>× {pick.users} {pr.seat_label}</span><b>{inr(each * pick.users * (per === "month" ? 12 : 1))}<small className="muted"> {per === "month" ? "/ 12 months" : "/ year"}</small></b>
                {setup > 0 && <><span>One-time set-up</span><b>{inr(setup)}</b></>}</div>
              <div style={{ display: "flex", gap: 8, marginTop: 10 }}>
                <button type="button" className="btn small" onClick={applyPicker}>{quoted.has(pr.code) ? "Update the quotation" : "Add to the quotation"}</button>
                <button type="button" className="btn ghost small" onClick={() => setPick(null)}>Cancel</button>
              </div>
            </div>;
          })()}
          <select defaultValue="" onChange={(e) => { if (e.target.value) addCost(e.target.value); e.target.value = ""; }} style={{ marginTop: 10, width: "100%" }}>
            <option value="">+ Add from the costing catalogue…</option>
            {costs.filter((c) => c.active).map((c) => <option key={c.id} value={c.id}>{c.name} — {inr(c.amount)} {BASIS[c.basis].label.toLowerCase()}</option>)}
          </select>
        </div>

        <div className="card">
          <h2>Totals</h2>
          <div className="formgrid" style={{ gridTemplateColumns: "minmax(0,1fr) minmax(0,1fr)" }}>
            <label className="field">Discount %<input {...NUM} value={q.discount_pct} onChange={(e) => set("discount_pct", Number(e.target.value) || 0)} /></label>
            <label className="field">GST %<input {...NUM} value={q.gst_rate} onChange={(e) => set("gst_rate", Number(e.target.value) || 0)} /></label>
          </div>
          <div className="tot" style={{ marginTop: 10 }}>
            <span>Recurring (subscriptions)</span><b>{inr(recurring)}</b>
            <span>One-time &amp; services</span><b>{inr(t.subtotal - recurring)}</b>
            {t.discount > 0 && <><span>Discount</span><b style={{ color: "var(--danger)" }}>− {inr(t.discount)}</b></>}
            <span>GST</span><b>{inr(t.gst)}</b>
          </div>
          <div className="grand"><span>Grand total</span><b>{inr(t.total)}</b></div>
          <label className="field" style={{ marginTop: 10 }}>Internal note (not printed)<input value={q.notes ?? ""} onChange={(e) => set("notes", e.target.value)} /></label>
          {msg.error && <div className="alert danger" style={{ marginTop: 10 }}>{msg.error}</div>}
          {msg.ok && <div className="alert ok" style={{ marginTop: 10 }}>{msg.ok}</div>}
          {/* check the PDF first, then save */}
          <div style={{ display: "grid", gridTemplateColumns: "minmax(0,1fr) minmax(0,1fr)", gap: 8, marginTop: 12 }}>
            <button type="button" className="btn" disabled={!!pdfBusy || busy} onClick={() => pdf(false)}>{pdfBusy === "view" ? "Preparing…" : "View PDF"}</button>
            <button type="button" className="btn secondary" disabled={!!pdfBusy || busy} onClick={() => pdf(true)}>{pdfBusy === "download" ? "Preparing…" : "Download PDF"}</button>
          </div>
          <button type="button" className="btn accent" style={{ width: "100%", marginTop: 8 }} disabled={busy || !!pdfBusy} onClick={() => save(false)}>{busy ? "Saving…" : initial?.id ? "Save changes" : "Save quotation"}</button>
          <p className="muted" style={{ fontSize: 12, marginTop: 8 }}>View or download the PDF of what is on screen — on the letterhead with the seal and signature{draft ? ", marked DRAFT until you mark it sent" : ""} — then save.{!initial?.id ? " The quotation number is given when you save." : ""}</p>
        </div>
        {children}
      </aside>
    </div>
  );
}
