import { requireStaff, isManager } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { AppShell } from "@/components/AppShell";
import { ActionForm } from "@/components/ActionForm";
import { Empty, fmtDate, one } from "@/components/ui";
import { fmtMoney } from "@/lib/money";
import { p } from "@/lib/base-path";
import { INVOICE_TONE } from "@/lib/view";
import { deletePrice, removeBillingImage, saveBillingSettings, savePrice, uploadBillingImage } from "@/app/billing-actions";
import { billingImageUrls } from "@/lib/billing-files";

export const metadata = { title: "Prices & invoices" };

type Price = { id: string; product_code: string; period: string; currency: string; unit_amount: number; min_seats: number; active: boolean; note: string | null };

export default async function Billing() {
  const staff = await requireStaff();
  const manager = isManager(staff);
  const supabase = await createClient();
  const [{ data: products }, { data: prices }, { data: s }, { data: invoices }] = await Promise.all([
    supabase.from("products").select("code,name,seat_label").eq("active", true).order("sort_order"),
    supabase.from("prices").select("*").order("product_code").order("period").order("currency"),
    supabase.from("billing_settings").select("*").eq("id", true).maybeSingle(),
    supabase.from("invoices").select("id,number,status,currency,total,issue_date,due_date,created_at,customer:customers(id,name,code)").order("created_at", { ascending: false }).limit(200),
  ]);
  const { data: reported } = await supabase.from("payments").select("invoice_id").eq("status", "reported");
  const toVerify = new Set((reported ?? []).map((r) => r.invoice_id));
  if (!s) {
    return <AppShell staff={staff} active="/billing"><div className="alert warn">Billing is not set up in the database yet. In Supabase → SQL Editor run <b>supabase/migrations/0018_billing.sql</b>, then refresh this page.</div></AppShell>;
  }
  const images = await billingImageUrls({ ...s, show_seal: true });
  const prodName = Object.fromEntries((products ?? []).map((x) => [x.code, x.name]));
  const seatLabel = Object.fromEntries((products ?? []).map((x) => [x.code, x.seat_label]));
  const inv = invoices ?? [];
  const today = new Date().toISOString().slice(0, 10);
  const due = inv.filter((i) => i.status === "issued");
  const overdue = due.filter((i) => i.due_date && i.due_date < today);
  const sum = (rows: typeof inv) => Object.entries(rows.reduce<Record<string, number>>((a, r) => ({ ...a, [r.currency]: (a[r.currency] ?? 0) + Number(r.total) }), {}))
    .map(([c, v]) => fmtMoney(v, c)).join(" + ") || "—";
  const month = today.slice(0, 7);

  return (
    <AppShell staff={staff} active="/billing">
      <div className="pagehead"><div><h1>Prices &amp; invoices</h1><p>Your price list, seller details for GST invoices, and every invoice. Create an invoice from a customer&apos;s page.</p></div></div>

      <div className="grid four">
        <div className="card stat"><div className="label">Waiting for payment</div><div className="value" style={{ fontSize: 20 }}>{sum(due)}</div><div className="hint">{due.length} issued invoice{due.length === 1 ? "" : "s"}</div></div>
        <div className="card stat"><div className="label">Overdue</div><div className="value" style={{ fontSize: 20, color: overdue.length ? "var(--danger)" : undefined }}>{overdue.length ? sum(overdue) : "None"}</div><div className="hint">Past the due date</div></div>
        <div className="card stat"><div className="label">Paid this month</div><div className="value" style={{ fontSize: 20, color: "var(--ok)" }}>{sum(inv.filter((i) => i.status === "paid" && (i.issue_date ?? "").slice(0, 7) === month))}</div><div className="hint">Invoices dated this month</div></div>
        <div className="card stat"><div className="label">Payments to verify</div><div className="value" style={{ fontSize: 20, color: toVerify.size ? "var(--warn)" : undefined }}>{toVerify.size || "None"}</div>
          <div className="hint">{toVerify.size ? "Customers reported a payment — check your bank statement" : s.bank_account_no ? `Paid into ${s.bank_name ?? "bank"} a/c …${String(s.bank_account_no).slice(-4)}` : "Add your bank account below"}</div></div>
      </div>

      <div className="card" style={{ marginTop: 16 }}>
        <h2>Invoices</h2>
        {inv.length ? (
          <div className="tablewrap"><table>
            <thead><tr><th>Invoice</th><th>Customer</th><th>Date</th><th>Due</th><th style={{ textAlign: "right" }}>Total</th><th>Status</th></tr></thead>
            <tbody>{inv.map((i) => {
              const c = one(i.customer as unknown as { id: string; name: string; code: string } | null);
              const late = i.status === "issued" && i.due_date && i.due_date < today;
              return (
                <tr key={i.id}>
                  <td><a href={p(`/invoices/${i.id}`)} className="mono"><b>{i.number ?? "Draft"}</b></a></td>
                  <td>{c ? <a href={p(`/customers/${c.id}`)}>{c.name}</a> : "—"}</td>
                  <td>{fmtDate(i.issue_date ?? i.created_at)}</td>
                  <td>{i.status === "issued" ? <span style={{ color: late ? "var(--danger)" : undefined }}>{fmtDate(i.due_date)}</span> : "—"}</td>
                  <td style={{ textAlign: "right", whiteSpace: "nowrap" }}>{fmtMoney(i.total, i.currency)}</td>
                  <td><span className={`badge ${late ? "danger" : INVOICE_TONE[i.status]}`}>{late ? "overdue" : i.status}</span>{i.status === "issued" && toVerify.has(i.id) && <span className="badge warn" style={{ marginLeft: 6 }}>payment to verify</span>}</td>
                </tr>);
            })}</tbody>
          </table></div>
        ) : <Empty>No invoices yet. Open a customer and use <b>Create invoice</b>.</Empty>}
      </div>

      <div className="card">
        <h2>Price list</h2>
        <p className="muted" style={{ marginTop: -4 }}>A price per user (per employee for the HRM) for each billing period and currency. <b>Minimum</b> is the fewest billed, however few are used. Customers are invoiced in their own currency, so add a price in every currency you sell in.</p>
        {prices?.length ? (
          <div className="tablewrap"><table>
            <thead><tr><th>Product</th><th>Billing</th><th style={{ textAlign: "right" }}>Price</th><th style={{ textAlign: "right" }}>Minimum</th><th>Note</th><th>Status</th>{manager && <th />}</tr></thead>
            <tbody>{(prices as Price[]).map((x) => (
              <tr key={x.id}>
                <td><b>{prodName[x.product_code] ?? x.product_code}</b></td>
                <td>{x.period === "year" ? "Yearly" : "Monthly"} · {x.currency}</td>
                <td style={{ textAlign: "right", whiteSpace: "nowrap" }}>{fmtMoney(x.unit_amount, x.currency)} <small>/ {seatLabel[x.product_code]?.replace(/s$/, "") ?? "user"}</small></td>
                <td style={{ textAlign: "right" }}>{x.min_seats}</td>
                <td><small>{x.note}</small></td>
                <td><span className={`badge ${x.active ? "ok" : ""}`}>{x.active ? "in use" : "paused"}</span></td>
                {manager && <td style={{ textAlign: "right" }}><form action={deletePrice}><input type="hidden" name="id" value={x.id} /><button className="btn secondary small">Remove</button></form></td>}
              </tr>))}</tbody>
          </table></div>
        ) : <Empty>No prices yet{manager ? " — add the first one below." : "."}</Empty>}
        {manager && (
          <div style={{ marginTop: 16, paddingTop: 14, borderTop: "1px solid var(--border)" }}>
            <h3>Add or change a price</h3>
            <div>
              <ActionForm action={savePrice} submitLabel="Save price" className="formgrid" resetOnSuccess>
                <label className="field">Product<select name="product_code" required>{(products ?? []).map((x) => <option key={x.code} value={x.code}>{x.name}</option>)}</select></label>
                <label className="field">Billing<select name="period" defaultValue="month"><option value="month">Monthly</option><option value="year">Yearly</option></select></label>
                <label className="field">Currency<input name="currency" defaultValue="INR" maxLength={3} required /></label>
                <label className="field">Price per user / employee<input name="unit_amount" inputMode="decimal" placeholder="e.g. 60" required /><span className="help">Before GST</span></label>
                <label className="field">Minimum billed<input name="min_seats" type="number" min={1} defaultValue={1} /></label>
                <label className="field">Status<select name="active" defaultValue="on"><option value="on">In use</option><option value="off">Paused</option></select></label>
                <label className="field full">Note (internal)<input name="note" placeholder="e.g. launch price till March" /></label>
              </ActionForm>
              <p className="muted" style={{ fontSize: 12.5 }}>Saving a product + billing + currency that already exists changes that price. Invoices already made keep their own prices.</p>
            </div>
          </div>
        )}
      </div>

      <div className="card">
        <h2>Seller details</h2>
        <p className="muted" style={{ marginTop: -4 }}>Printed on every invoice and frozen on it when issued. With a GSTIN, invoices are <b>Tax Invoices</b>: CGST + SGST for customers in your state, IGST for other states, and zero-rated export under LUT for customers abroad. Without a GSTIN, no GST is charged.</p>
        {(!s.address || (!s.bank_account_no && !s.upi_id)) && <div className="alert warn">Fill in your address and bank account (or UPI ID) before issuing the first invoice.</div>}
        {manager ? (
          <ActionForm action={saveBillingSettings} submitLabel="Save seller details" className="formgrid">
            <label className="field">Trade name<input name="trade_name" defaultValue={s.trade_name ?? ""} placeholder="As on the GST certificate" /><span className="help">The name invoices lead with</span></label>
            <label className="field">Legal name<input name="legal_name" defaultValue={s.legal_name} required /><span className="help">As on the GST certificate (the proprietor for a proprietorship)</span></label>
            <label className="field">Constitution<select name="constitution" defaultValue={s.constitution ?? ""}><option value=""></option>{["Proprietorship", "Partnership", "LLP", "Private Limited Company", "Public Limited Company", "One Person Company"].map((x) => <option key={x}>{x}</option>)}</select></label>
            <label className="field">GSTIN<input name="gstin" defaultValue={s.gstin ?? ""} placeholder="34ABCDE1234F1Z5" maxLength={15} /></label>
            <label className="field">PAN<input name="pan" defaultValue={s.pan ?? ""} maxLength={10} /><span className="help">Printed on invoices; never shown on the website</span></label>
            <label className="field">Udyam (MSME) number<input name="udyam_no" defaultValue={s.udyam_no ?? ""} placeholder="UDYAM-PY-03-0000000" /></label>
            <label className="field">MSME category<select name="msme_category" defaultValue={s.msme_category ?? ""}><option value=""></option><option>Micro</option><option>Small</option><option>Medium</option></select></label>
            <label className="field">Website<input name="website" defaultValue={s.website ?? ""} placeholder="www.kmr-groups.com" /></label>
            <label className="field full">Address<input name="address" defaultValue={s.address ?? ""} /></label>
            <label className="field">City<input name="city" defaultValue={s.city ?? ""} /></label>
            <label className="field">State<input name="state" defaultValue={s.state ?? ""} placeholder="Karnataka" /></label>
            <label className="field">State code<input name="state_code" defaultValue={s.state_code ?? ""} placeholder="29" maxLength={2} /><span className="help">First 2 digits of the GSTIN</span></label>
            <label className="field">PIN code<input name="postal_code" defaultValue={s.postal_code ?? ""} /></label>
            <label className="field">Email<input name="email" type="email" defaultValue={s.email ?? ""} /></label>
            <label className="field">Phone<input name="phone" defaultValue={s.phone ?? ""} /></label>
            <label className="field">Invoice prefix<input name="invoice_prefix" defaultValue={s.invoice_prefix} maxLength={10} required /><span className="help">Numbers like {s.invoice_prefix}/26-27/0001</span></label>
            <label className="field">SAC code<input name="sac_code" defaultValue={s.sac_code} required /><span className="help">998314 — IT design &amp; development services</span></label>
            <label className="field">GST rate (%)<input name="gst_rate" inputMode="decimal" defaultValue={String(s.gst_rate)} required /></label>
            <label className="field">Payment due (days)<input name="payment_days" type="number" min={0} max={120} defaultValue={s.payment_days} required /></label>
            <label className="field">LUT number (exports)<input name="lut_no" defaultValue={s.lut_no ?? ""} placeholder="AD290326000123X" /></label>
            <div className="field full" style={{ marginTop: 6 }}><b>Bank account for payments</b><span className="help">Customers pay into this account by NEFT / RTGS / IMPS; it is printed on every invoice and pay link.</span></div>
            <label className="field">Account name<input name="bank_account_name" defaultValue={s.bank_account_name ?? ""} placeholder="As in the bank's records" /></label>
            <label className="field">Account number<input name="bank_account_no" defaultValue={s.bank_account_no ?? ""} inputMode="numeric" /></label>
            <label className="field">IFSC<input name="bank_ifsc" defaultValue={s.bank_ifsc ?? ""} maxLength={11} placeholder="FDRL0002514" /></label>
            <label className="field">Bank<input name="bank_name" defaultValue={s.bank_name ?? ""} placeholder="Federal Bank" /></label>
            <label className="field">Branch<input name="bank_branch" defaultValue={s.bank_branch ?? ""} /></label>
            <label className="field">Account type<input name="bank_account_type" defaultValue={s.bank_account_type ?? ""} placeholder="Current account" /></label>
            <label className="field">SWIFT (customers abroad)<input name="bank_swift" defaultValue={s.bank_swift ?? ""} maxLength={11} /></label>
            <label className="field">UPI ID<input name="upi_id" defaultValue={s.upi_id ?? ""} placeholder="kmrgroups@fbl" /><span className="help">The pay link shows a UPI QR with the amount filled in</span></label>
            <label className="field full">Other payment notes<textarea name="bank_details" rows={2} defaultValue={s.bank_details ?? ""} placeholder="e.g. Cheques payable to KMR GROUP OF COMPANIES." /></label>
            <label className="field full">Terms<textarea name="terms" rows={2} defaultValue={s.terms ?? ""} placeholder="Subscription renews on payment. Prices exclude GST unless stated." /></label>
            <div className="field full" style={{ marginTop: 6 }}><b>Authorised signatory</b></div>
            <label className="field">Name<input name="signatory_name" defaultValue={s.signatory_name ?? ""} placeholder="R. Rajavelu" /></label>
            <label className="field">Designation<input name="signatory_title" defaultValue={s.signatory_title ?? ""} placeholder="Proprietor" /></label>
            <label className="field full checkline"><input type="checkbox" name="show_seal" defaultChecked={s.show_seal !== false} /> Show the seal and signature on invoices</label>
            <label className="field full checkline"><input type="checkbox" name="show_msme_note" defaultChecked={s.show_msme_note !== false} /> Show the MSME note (MSMED Act, 2006 — payment within 45 days) when a Udyam number is set</label>
          </ActionForm>
        ) : <p className="muted">Only an owner or administrator can change these.</p>}
      </div>

      <div className="card">
        <h2>Seal &amp; signature</h2>
        <p className="muted" style={{ marginTop: -4 }}>Printed in the signature block of new invoices. Kept private — shown only on invoices, through links that expire. A PNG with a transparent background looks best.</p>
        <div className="grid two">
          {(["seal", "signature"] as const).map((kind) => (
            <div key={kind} style={{ border: "1px solid var(--border)", borderRadius: 10, padding: 14 }}>
              <b>{kind === "seal" ? "Company seal" : "Signature"}</b>
              <div style={{ height: 120, display: "grid", placeItems: "center", background: "var(--surface-2)", borderRadius: 8, margin: "8px 0" }}>
                {images[kind] ? <img src={images[kind]!} alt="" style={{ maxHeight: 110, maxWidth: "90%", objectFit: "contain" }} /> : <small className="muted">None yet</small>}
              </div>
              {manager && <>
                <ActionForm action={uploadBillingImage} submitLabel={images[kind] ? "Replace" : "Upload"} variant="secondary" hidden={{ kind }}>
                  <input type="file" name="image" accept="image/png,image/jpeg,image/webp" required />
                </ActionForm>
                {images[kind] && <form action={removeBillingImage} style={{ marginTop: 6 }}><input type="hidden" name="kind" value={kind} /><button className="linkbtn">Remove from new invoices</button></form>}
              </>}
            </div>
          ))}
        </div>
      </div>
    </AppShell>
  );
}
