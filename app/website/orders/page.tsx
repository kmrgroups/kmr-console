import { requireStaff } from "@/lib/auth";
import { AppShell } from "@/components/AppShell";
import { ActionForm } from "@/components/ActionForm";
import { Empty, fmtDateTime } from "@/components/ui";
import { web } from "@/lib/manage-server";
import { env } from "@/lib/env";
import { p } from "@/lib/base-path";
import { confirmOrderPayment, rejectOrderPayment, cancelShopOrder } from "@/app/website-actions";

export const metadata = { title: "Shop orders" };
const LABEL: Record<string, [string, string]> = {
  awaiting_payment: ["awaiting payment", "info"], payment_reported: ["payment reported", "warn"], paid: ["paid", "ok"], cancelled: ["cancelled", ""], failed: ["failed", "danger"], created: ["created", ""],
};
const METHODS: [string, string][] = [["neft", "NEFT"], ["imps", "IMPS"], ["rtgs", "RTGS"], ["upi", "UPI"], ["cheque", "Cheque"], ["other", "Other"]];
const inr = (n: number) => `₹${Number(n).toLocaleString("en-IN", { maximumFractionDigits: 2 })}`;

export default async function ShopOrders({ searchParams }: { searchParams: Promise<{ s?: string }> }) {
  const staff = await requireStaff();
  const { s } = await searchParams;
  const can = ["owner", "admin", "sales"].includes(staff.role);
  let q = web().from("orders").select("*").order("created_at", { ascending: false }).limit(300);
  if (s) q = q.eq("status", s);
  const { data: orders, error } = await q;
  const today = new Date().toISOString().slice(0, 10);
  return (
    <AppShell staff={staff} active="/website">
      <div className="pagehead"><div><p style={{ margin: 0 }}><a href={p("/website")} className="muted">← Website</a></p><h1>Shop orders</h1>
        <p>Customers pay by bank transfer / UPI into the account in Prices &amp; invoices › Seller details and report the UTR on their order page. Check your bank statement, then confirm. Stock is reduced only when an order is paid.</p></div></div>
      <form className="row" style={{ marginBottom: 12 }}>
        <select name="s" defaultValue={s ?? ""} style={{ maxWidth: 240 }}><option value="">All orders</option>{Object.entries(LABEL).filter(([k]) => k !== "created").map(([k, [l]]) => <option key={k} value={k}>{l}</option>)}</select>
        <button className="btn secondary">Show</button>
      </form>
      {error && <div className="alert error">{error.message}</div>}
      {orders?.length ? orders.map((o) => {
        const [label, tone] = LABEL[o.status] ?? [o.status, ""];
        const unpaid = ["awaiting_payment", "payment_reported", "created"].includes(o.status);
        const diff = o.paid_amount != null ? Number(o.paid_amount) - Number(o.amount) : 0;
        return (
          <div key={o.id} className="card" style={o.status === "payment_reported" ? { borderColor: "var(--warn)" } : undefined}>
            <div className="spread">
              <div><b className="mono">{o.order_no ?? o.razorpay_order_id}</b> · {o.product_name} × {o.quantity} · <b>{inr(o.amount)}</b></div>
              <span className={`badge ${tone}`}>{label}</span>
            </div>
            <p style={{ margin: "6px 0 0", fontSize: 14 }}>{o.customer_name} · {o.customer_phone}{o.customer_email ? ` · ${o.customer_email}` : ""}</p>
            <p className="muted" style={{ margin: "2px 0 0", fontSize: 13, whiteSpace: "pre-line" }}>{o.shipping_address}</p>
            {o.pay_reference && <p style={{ margin: "8px 0 0", fontSize: 14 }}>Payment: <b>{String(o.pay_method ?? "").toUpperCase()}</b> · <span className="mono"><b>{o.pay_reference}</b></span>{o.paid_amount != null ? ` · ${inr(o.paid_amount)}` : ""} · {o.paid_on}{o.payer_name ? ` · from ${o.payer_name}` : ""}
              {diff !== 0 && <span style={{ color: "var(--warn)" }}> — {diff < 0 ? `${inr(-diff)} less` : `${inr(diff)} more`} than the order</span>}</p>}
            {o.reject_reason && unpaid && <p style={{ margin: "4px 0 0", fontSize: 13, color: "var(--danger)" }}>Last report rejected: {o.reject_reason}</p>}
            <p className="muted" style={{ margin: "4px 0 0", fontSize: 12.5 }}>Placed {fmtDateTime(o.created_at)}{o.confirmed_at ? ` · confirmed ${fmtDateTime(o.confirmed_at)}${o.confirmed_by ? ` by ${o.confirmed_by}` : ""}` : ""}
              {o.order_token && <> · <a href={`${env.platformUrl}/order/${o.order_token}`} target="_blank" rel="noopener">customer&apos;s order page</a></>}</p>
            {can && unpaid && (
              <div className="row" style={{ marginTop: 10, alignItems: "flex-start" }}>
                {o.status === "payment_reported" && <ActionForm action={confirmOrderPayment} submitLabel="Confirm — money received" hidden={{ id: o.id }} confirm={`Is ${inr(o.paid_amount ?? o.amount)} with reference ${o.pay_reference} in your bank account?`} />}
                {o.status === "payment_reported" && (
                  <details><summary className="btn secondary small">Reject</summary><div style={{ marginTop: 8 }}>
                    <ActionForm action={rejectOrderPayment} submitLabel="Reject report" variant="danger" hidden={{ id: o.id }}><label className="field">Reason (the customer sees it)<input name="reason" required placeholder="UTR not found in our statement" /></label></ActionForm></div></details>)}
                {o.status !== "payment_reported" && (
                  <details><summary className="btn secondary small">Mark as paid</summary><div style={{ marginTop: 8 }}>
                    <ActionForm action={confirmOrderPayment} submitLabel="Record payment" hidden={{ id: o.id }} className="formgrid">
                      <label className="field">Paid by<select name="pay_method" defaultValue="neft">{METHODS.map(([k, l]) => <option key={k} value={k}>{l}</option>)}</select></label>
                      <label className="field">Reference<input name="reference" required placeholder="UTR / cheque no." /></label>
                      <label className="field">Received on<input type="date" name="paid_on" defaultValue={today} max={today} /></label>
                    </ActionForm></div></details>)}
                <details><summary className="btn secondary small">Cancel order</summary><div style={{ marginTop: 8 }}>
                  <ActionForm action={cancelShopOrder} submitLabel="Cancel order" variant="danger" hidden={{ id: o.id }}><label className="field">Reason (optional)<input name="reason" /></label></ActionForm></div></details>
              </div>
            )}
          </div>);
      }) : !error && <div className="card"><Empty>No orders{s ? " with this status" : " yet"}.</Empty></div>}
    </AppShell>
  );
}
