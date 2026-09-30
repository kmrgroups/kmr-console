import QRCode from "qrcode";
import { requireStaff, isManager } from "@/lib/auth";
import { ActionForm } from "@/components/ActionForm";
import { createClient } from "@/lib/supabase/server";
import { gatewayStatus, web } from "@/lib/cms-server";
import { env } from "@/lib/env";
import { p } from "@/lib/base-path";
import { savePaymentSettings } from "@/app/cms-actions";

export const metadata = { title: "Payment settings" };
const mask = (s?: string | null) => (s ? `•••• ${s.replace(/\s/g, "").slice(-4)}` : "—");

/** How website customers pay, and a check that the money goes to KMR's own account. */
export default async function Payments() {
  const staff = await requireStaff();
  const supabase = await createClient();
  const [{ data: st }, { data: b }, gw] = await Promise.all([
    web().from("site_settings").select("online_payment,bank_transfer").maybeSingle(),
    supabase.from("billing_settings").select("legal_name,trade_name,bank_account_name,bank_account_no,bank_ifsc,bank_name,bank_branch,upi_id").maybeSingle(),
    gatewayStatus(env.platformUrl),
  ]);
  const payee = b?.bank_account_name || b?.trade_name || b?.legal_name || "KMR";
  const upi = b?.upi_id ? `upi://pay?pa=${encodeURIComponent(b.upi_id)}&pn=${encodeURIComponent(payee)}&am=1.00&cu=INR&tn=${encodeURIComponent("Test payment")}` : null;
  const qr = upi ? await QRCode.toString(upi, { type: "svg", margin: 1, width: 150 }) : null;
  const checks: [boolean, string][] = [
    [Boolean(b?.bank_account_no && b?.bank_ifsc), `Bank account ${mask(b?.bank_account_no)} · IFSC ${b?.bank_ifsc ?? "missing"} · ${[b?.bank_name, b?.bank_branch].filter(Boolean).join(", ") || "bank name missing"}`],
    [Boolean(b?.upi_id), b?.upi_id ? `UPI ID ${b.upi_id} — make sure it is linked to the same account` : "UPI ID missing — customers can still pay by bank transfer"],
    [Boolean(b?.bank_account_name), b?.bank_account_name ? `Account holder: ${b.bank_account_name}` : "Account holder name missing"],
  ];

  return (
    <>
      <div className="pagehead"><div><h1>Payment settings</h1>
        <p>Two ways to pay on every order page. Both put the money into KMR’s own bank account — no one else’s.</p></div>
        <a className="btn secondary" href={p("/cms/orders")}>Orders &amp; payments</a></div>

      <div className="grid two">
        <div className="card">
          <h2>Online payment — Razorpay <span className={`badge ${gw.configured ? "ok" : "warn"}`}>{gw.configured ? `keys set · ${gw.mode} mode` : gw.reachable ? "keys not set" : "website not reachable"}</span></h2>
          <p className="muted" style={{ marginTop: -4 }}>UPI, cards, net banking and wallets through Razorpay’s checkout. The website’s server checks every payment with Razorpay before marking the order paid; a webhook catches payments if the customer closes the page early.</p>
          <ul style={{ fontSize: 14, paddingLeft: 18, margin: "8px 0" }}>
            <li>Razorpay pays out to the <b>settlement bank account in your Razorpay dashboard</b> (Account &amp; Settings › Bank account). It must be KMR’s account {mask(b?.bank_account_no)} ({b?.bank_ifsc ?? "IFSC"}), the same as below.</li>
            <li>Keys go in the <b>website’s</b> Vercel settings: <code>RAZORPAY_KEY_ID</code>, <code>RAZORPAY_KEY_SECRET</code>, <code>RAZORPAY_WEBHOOK_SECRET</code>{gw.key ? <> — current key <code>{gw.key}</code></> : null}.</li>
            <li>Webhook URL (Razorpay › Webhooks, events <i>payment.captured</i> and <i>order.paid</i>): <code>{env.platformUrl}/api/pay/razorpay/webhook</code> {gw.configured && <span className={`badge ${gw.webhook ? "ok" : "warn"}`}>{gw.webhook ? "secret set" : "secret not set"}</span>}</li>
          </ul>
        </div>
        <div className="card">
          <h2>Bank transfer / UPI <a className="btn secondary small" href={p("/billing")}>Edit Seller details</a></h2>
          <p className="muted" style={{ marginTop: -4 }}>The order page shows these details and a UPI QR with the exact amount and order number. The customer reports the UTR; you confirm it in Orders &amp; payments. The same account is printed on invoices.</p>
          <ul style={{ listStyle: "none", padding: 0, margin: "8px 0", fontSize: 14 }}>
            {checks.map(([ok, t]) => <li key={t} style={{ padding: "3px 0" }}><span className={`badge ${ok ? "ok" : "warn"}`}>{ok ? "✓" : "!"}</span> {t}</li>)}
          </ul>
          {qr && <div className="row" style={{ alignItems: "center" }}><div dangerouslySetInnerHTML={{ __html: qr }} style={{ width: 150 }} />
            <small className="muted">Test it: scan with any UPI app — it should show <b>{payee}</b> and ₹1.00. Cancel before paying, or pay ₹1 and check it arrives.</small></div>}
        </div>
      </div>

      <div className="card">
        <h2>Ways to pay shown to customers</h2>
        {isManager(staff) ? (
          <ActionForm action={savePaymentSettings} submitLabel="Save" pendingLabel="Saving…">
            <label className="checkline"><input type="checkbox" name="online_payment" defaultChecked={Boolean(st?.online_payment)} /> Online payment (Razorpay) {!gw.configured && <small className="muted"> — needs the keys above; until then customers only see bank / UPI</small>}</label>
            <label className="checkline"><input type="checkbox" name="bank_transfer" defaultChecked={st?.bank_transfer !== false} /> Bank transfer / UPI</label>
          </ActionForm>
        ) : <p className="muted">Online payment: {st?.online_payment ? "on" : "off"} · Bank / UPI: {st?.bank_transfer !== false ? "on" : "off"}. Only an owner or administrator can change this.</p>}
      </div>
    </>
  );
}
