"use client";
import { useState } from "react";
import { p } from "@/lib/base-path";

/** A value with a Copy button (account number, IFSC …) */
export function CopyValue({ value }: { value: string }) {
  const [done, setDone] = useState(false);
  return (
    <button type="button" className="linkbtn" style={{ fontSize: 12, marginLeft: 8 }}
      onClick={() => { navigator.clipboard?.writeText(value); setDone(true); setTimeout(() => setDone(false), 1500); }}>
      {done ? "Copied" : "Copy"}
    </button>
  );
}

const METHODS: [string, string][] = [["neft", "NEFT"], ["imps", "IMPS"], ["rtgs", "RTGS"], ["upi", "UPI"], ["cheque", "Cheque"], ["other", "Other"]];

/** "I've paid": the customer tells KMR the UTR / reference so KMR can match it in the bank statement. */
export function ReportPaymentForm({ token, amount, currency }: { token: string; amount: string; currency: string }) {
  const today = new Date().toISOString().slice(0, 10);
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState<{ ok?: string; error?: string }>({});

  async function submit(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    const f = new FormData(e.currentTarget);
    setBusy(true); setMsg({});
    try {
      const r = await fetch(p("/api/pay/report"), { method: "POST", headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ token, method: f.get("pay_method"), reference: f.get("reference"), paid_on: f.get("paid_on"), amount: f.get("amount"), payer: f.get("payer") }) });
      const j = await r.json().catch(() => ({}));
      if (!r.ok) throw new Error(j.error || "Could not send. Please try again.");
      setMsg({ ok: "Thank you — we have your payment details. KMR will confirm once it shows in our bank account (usually within one working day)." });
      setTimeout(() => window.location.reload(), 1800);
    } catch (err) { setMsg({ error: (err as Error).message }); setBusy(false); }
  }

  return (
    <form onSubmit={submit} className="formgrid">
      <label className="field">Paid by<select name="pay_method" defaultValue={currency === "INR" ? "neft" : "other"}>{METHODS.map(([k, v]) => <option key={k} value={k}>{v}</option>)}</select></label>
      <label className="field">UTR / transaction reference<input name="reference" required minLength={4} maxLength={60} placeholder="e.g. FDRLN26273012345" /><span className="help">From your bank&apos;s confirmation or UPI app</span></label>
      <label className="field">Date paid<input type="date" name="paid_on" defaultValue={today} max={today} required /></label>
      <label className="field">Amount paid ({currency})<input name="amount" inputMode="decimal" defaultValue={amount} required /><span className="help">If TDS was deducted, enter the amount actually paid</span></label>
      <label className="field full">Paid from (company / account name, optional)<input name="payer" maxLength={120} /></label>
      <div className="field full"><button className="btn" disabled={busy}>{busy ? "Sending…" : "Send payment details"}</button></div>
      {msg.error && <div className="alert error full" role="alert">{msg.error}</div>}
      {msg.ok && <div className="alert ok full" role="status">{msg.ok}</div>}
    </form>
  );
}
