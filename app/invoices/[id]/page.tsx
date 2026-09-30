import { notFound } from "next/navigation";
import { requireStaff, isManager } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { AppShell } from "@/components/AppShell";
import { ActionForm, CopyLink } from "@/components/ActionForm";
import { InvoiceDoc, type InvoiceData, type LineData, type Party } from "@/components/InvoiceDoc";
import { PrintButton } from "@/components/PrintButton";
import { fmtDate, fmtDateTime } from "@/components/ui";
import { fmtMoney } from "@/lib/money";
import { razorpay } from "@/lib/razorpay";
import { env } from "@/lib/env";
import { BASE_PATH, p } from "@/lib/base-path";
import { INVOICE_TONE } from "@/lib/view";
import { platformBrand } from "@/lib/brand";
import { addInvoiceLine, cancelInvoice, discardInvoice, issueInvoice, markInvoicePaid, removeInvoiceLine } from "@/app/billing-actions";

export const metadata = { title: "Invoice" };

export default async function InvoicePage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const staff = await requireStaff();
  const manager = isManager(staff);
  const supabase = await createClient();
  const { data: inv } = await supabase.from("invoices").select("*").eq("id", id).maybeSingle();
  if (!inv) notFound();
  const [{ data: lines }, { data: payments }, { data: c }, { data: s }, brand] = await Promise.all([
    supabase.from("invoice_lines").select("*").eq("invoice_id", id).order("sort").order("id"),
    supabase.from("payments").select("*").eq("invoice_id", id).order("created_at", { ascending: false }),
    supabase.from("customers").select("*").eq("id", inv.customer_id).maybeSingle(),
    supabase.from("billing_settings").select("*").eq("id", true).maybeSingle(),
    platformBrand(),
  ]);
  const draft = inv.status === "draft";
  // Drafts show today's seller and customer details; issued invoices show what was frozen on them
  const seller: Party = draft ? { ...(s ?? {}), state_code: s?.state_code ?? s?.gstin?.slice(0, 2) } : inv.seller;
  const buyer: Party = draft && c ? { code: c.code, name: c.legal_name || c.name, tax_id: c.tax_id, address: c.address, city: c.city, state: c.state, postal_code: c.postal_code, country: c.country, contact_name: c.contact_name, contact_email: c.contact_email } : inv.buyer;
  const payLink = `${env.platformUrl}${BASE_PATH}/pay/${inv.pay_token}`;
  const today = new Date().toISOString().slice(0, 10);
  const late = inv.status === "issued" && inv.due_date && inv.due_date < today;

  return (
    <AppShell staff={staff} active="/billing">
      <div className="pagehead noprint">
        <div><h1>{inv.number ?? "Draft invoice"}</h1>
          <p>{c && <a href={p(`/customers/${c.id}`)}>{c.name}</a>} · {fmtMoney(inv.total, inv.currency)} · <span className={`badge ${late ? "danger" : INVOICE_TONE[inv.status]}`}>{late ? "overdue" : inv.status}</span></p></div>
        <div className="row"><a className="btn secondary" href={p("/billing")}>All invoices</a><PrintButton /></div>
      </div>

      <div className="invoice-layout">
        <InvoiceDoc inv={inv as InvoiceData} lines={(lines ?? []) as LineData[]} seller={seller} buyer={buyer} logoUrl={brand.logo_url} />

        <aside className="stack noprint">
          {draft && manager && (
            <div className="card">
              <h2>Draft</h2>
              <p className="muted" style={{ fontSize: 13 }}>Check the lines and details. Issuing gives it the next number and freezes it — after that it can only be cancelled, not changed.</p>
              {!s?.address && <div className="alert warn">Add your seller details under <a href={p("/billing")}>Prices &amp; invoices</a> first.</div>}
              <ActionForm action={issueInvoice} submitLabel="Issue invoice" pendingLabel="Issuing…" hidden={{ invoice_id: inv.id }} confirm="Issue this invoice? It gets the next number and can no longer be changed." />
              <details style={{ marginTop: 12 }}>
                <summary className="btn secondary small">Add a line</summary>
                <div style={{ marginTop: 10 }}>
                  <ActionForm action={addInvoiceLine} submitLabel="Add line" hidden={{ invoice_id: inv.id }} resetOnSuccess>
                    <label className="field">Description<input name="description" placeholder="Onboarding and training (1 day)" required /></label>
                    <div className="row"><label className="field" style={{ flex: 1 }}>Qty<input name="qty" inputMode="decimal" defaultValue="1" required /></label>
                      <label className="field" style={{ flex: 2 }}>Rate ({inv.currency})<input name="unit_amount" inputMode="decimal" required /></label></div>
                  </ActionForm>
                </div>
              </details>
              {(lines ?? []).length > 0 && (
                <div style={{ marginTop: 12 }}>
                  <small className="muted">Remove a line</small>
                  {(lines ?? []).map((l) => (
                    <form key={l.id} action={removeInvoiceLine} className="spread" style={{ padding: "6px 0", borderBottom: "1px solid var(--border)", fontSize: 13 }}>
                      <input type="hidden" name="invoice_id" value={inv.id} /><input type="hidden" name="line_id" value={l.id} />
                      <span style={{ flex: 1 }}>{l.description}</span><button className="btn secondary small">Remove</button>
                    </form>))}
                </div>
              )}
              <div style={{ marginTop: 14 }}><ActionForm action={discardInvoice} submitLabel="Discard draft" variant="danger" hidden={{ invoice_id: inv.id, customer_id: inv.customer_id }} confirm="Delete this draft?" /></div>
            </div>
          )}

          {inv.status === "issued" && (
            <div className="card">
              <h2>Get paid</h2>
              <p className="muted" style={{ fontSize: 13, marginTop: -4 }}>Due {fmtDate(inv.due_date)}{late ? " — overdue" : ""}.</p>
              <b style={{ fontSize: 14 }}>Pay link</b>
              <p className="muted" style={{ fontSize: 13, margin: "2px 0 6px" }}>The customer sees this invoice and {razorpay.configured ? <>pays with card, UPI or net banking through Razorpay{razorpay.mode === "test" ? <> — <b>test mode</b>: use Razorpay test cards, no real money moves</> : null}.</> : "your bank / UPI details. Add Razorpay keys to take online payments."} Their company administrators also find it in their KMR portal.</p>
              <div className="copybox"><input readOnly value={payLink} /><a className="btn secondary small" href={payLink} target="_blank" rel="noopener">Open</a></div>
              {manager && (
                <>
                  <details style={{ marginTop: 14 }}>
                    <summary className="btn small">Mark as paid</summary>
                    <div style={{ marginTop: 10 }}>
                      <ActionForm action={markInvoicePaid} submitLabel="Record payment" hidden={{ invoice_id: inv.id }}>
                        <label className="field">Reference<input name="reference" placeholder="UTR / cheque no. / UPI ref" required /></label>
                        <label className="field">Received on<input type="date" name="paid_on" defaultValue={today} max={today} /></label>
                      </ActionForm>
                      <p className="muted" style={{ fontSize: 12.5 }}>For bank transfers, cheques or UPI to your account. The licences renew for the paid period.</p>
                    </div>
                  </details>
                  <details style={{ marginTop: 10 }}>
                    <summary className="btn secondary small">Cancel invoice</summary>
                    <div style={{ marginTop: 10 }}>
                      <ActionForm action={cancelInvoice} submitLabel="Cancel invoice" variant="danger" hidden={{ invoice_id: inv.id }} confirm="Cancel this invoice? Its number stays in the series, marked cancelled.">
                        <label className="field">Reason<input name="reason" required placeholder="e.g. wrong number of users — reissued" /></label>
                      </ActionForm>
                    </div>
                  </details>
                </>
              )}
            </div>
          )}

          {inv.status === "paid" && <div className="card"><h2>Paid</h2><p style={{ margin: 0 }}>Paid on <b>{fmtDate(inv.paid_at)}</b>. The customer&apos;s licences were renewed for the paid period.</p>
            <p className="muted" style={{ fontSize: 13, margin: "8px 0 0" }}>Receipt link for the customer:</p><CopyLink link={payLink} /></div>}

          <div className="card">
            <h2>Payments</h2>
            {payments?.length ? (
              <ul className="timeline">{payments.map((x) => (
                <li key={x.id}><span><b>{x.provider === "manual" ? "Recorded by hand" : "Razorpay"}</b>{x.provider === "razorpay" && <span className={`badge ${x.mode === "live" ? "ok" : "warn"}`} style={{ marginLeft: 6 }}>{x.mode}</span>} · {fmtMoney(x.amount, x.currency)} · {x.status}
                  <br /><small className="mono">{x.reference ?? x.payment_id ?? x.order_id}</small></span><small>{fmtDateTime(x.paid_at ?? x.created_at)}</small></li>))}</ul>
            ) : <p className="muted" style={{ margin: 0 }}>None yet.</p>}
          </div>
        </aside>
      </div>
    </AppShell>
  );
}
