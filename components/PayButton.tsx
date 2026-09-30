"use client";
import { useState } from "react";
import { p } from "@/lib/base-path";

declare global { interface Window { Razorpay?: new (o: Record<string, unknown>) => { open: () => void; on: (e: string, f: (r: { error?: { description?: string } }) => void) => void } } }

function loadCheckout(): Promise<void> {
  if (window.Razorpay) return Promise.resolve();
  return new Promise((ok, bad) => {
    const s = document.createElement("script");
    s.src = "https://checkout.razorpay.com/v1/checkout.js";
    s.onload = () => ok(); s.onerror = () => bad(new Error("Could not load Razorpay. Check your connection and try again."));
    document.body.append(s);
  });
}

/** Opens Razorpay Checkout for one invoice; the server creates the order and verifies the payment. */
export function PayButton({ token, label, test }: { token: string; label: string; test: boolean }) {
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState<{ ok?: string; error?: string }>({});

  async function pay() {
    setBusy(true); setMsg({});
    try {
      await loadCheckout();
      const r = await fetch(p("/api/pay/order"), { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ token }) });
      const o = await r.json();
      if (!r.ok) throw new Error(o.error || "Could not start the payment.");
      const rzp = new window.Razorpay!({
        key: o.key, order_id: o.order_id, amount: o.amount, currency: o.currency, name: o.name, description: o.description,
        prefill: o.prefill, notes: o.notes, theme: { color: "#1F3A5F" },
        modal: { ondismiss: () => setBusy(false) },
        handler: async (resp: Record<string, string>) => {
          setMsg({ ok: "Payment received — confirming…" });
          const v = await fetch(p("/api/pay/verify"), { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ token, ...resp }) });
          const vr = await v.json();
          if (!v.ok) { setMsg({ error: vr.error || "We could not confirm the payment. If money was taken, it will be matched automatically — please contact KMR." }); setBusy(false); return; }
          setMsg({ ok: "Paid. Thank you!" }); window.location.reload();
        },
      });
      rzp.on("payment.failed", (e) => { setMsg({ error: e.error?.description || "The payment failed. You can try again." }); setBusy(false); });
      rzp.open();
    } catch (e) { setMsg({ error: (e as Error).message }); setBusy(false); }
  }

  return (
    <div className="stack" style={{ gap: 6, alignItems: "flex-end" }}>
      <button className="btn accent" onClick={pay} disabled={busy} style={{ minWidth: 200 }}>{busy ? "Please wait…" : label}</button>
      {test && <small className="muted">Test mode — use a Razorpay test card or UPI <span className="mono">success@razorpay</span>; no real money moves.</small>}
      {msg.error && <div className="alert error" role="alert">{msg.error}</div>}
      {msg.ok && <div className="alert ok" role="status">{msg.ok}</div>}
    </div>
  );
}
