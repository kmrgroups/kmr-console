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
import { createAdminClient } from "@/lib/supabase/admin";
import { deleteCostItem, saveCostItem, saveQuoteSettings } from "@/app/quote-actions";
import { BASIS, inr } from "@/lib/quote";

const TABS = [["quotes", "Quotations"], ["invoices", "Invoices"], ["costing", "Price list & costing"], ["seller", "Seller & letterhead"]] as const;
const QUOTE_TONE: Record<string, string> = { draft: "", sent: "info", accepted: "ok", declined: "danger", expired: "warn" };
type Cost = { id: string; product_code: string | null; name: string; detail: string | null; basis: keyof typeof BASIS; amount: number; default_qty: number; include_by_default: boolean; sort_order: number; active: boolean };

export const metadata = { title: "Prices & invoices" };

type Price = { id: string; product_code: string; period: string; currency: string; unit_amount: number; min_seats: number; active: boolean; note: string | null };

export default async function Billing({ searchParams }: { searchParams: Promise<{ tab?: string }> }) {
  const tab = (await searchParams).tab ?? "quotes";
  const staff = await requireStaff();
  const manager = isManager(staff);
  const supabase = await createClient();
  const [{ data: products }, { data: prices }, { data: s }, { data: invoices }] = await Promise.all([
    supabase.from("products").select("code,name,seat_label").eq("active", true).order("sort_order"),
    supabase.from("prices").select("*").order("product_code").order("period").order("currency"),
    supabase.from("billing_settings").select("*").eq("id", true).maybeSingle(),
    supabase.from("invoices").select("id,number,status,currency,total,issue_date,due_date,created_at,customer:customers(id,name,code)").order("created_at", { ascending: false }).limit(200),
  ]);
  const [{ data: quotes }, { data: costs }] = await Promise.all([
    supabase.from("quotes").select("id,number,to_name,subject,total,status,quote_date,valid_until,created_by").order("created_at", { ascending: false }).limit(200),
    supabase.from("cost_items").select("*").order("sort_order").order("name"),
  ]);
  const { data: reported } = await supabase.from("payments").select("invoice_id").eq("status", "reported");
  const toVerify = new Set((reported ?? []).map((r) => r.invoice_id));
  if (!s) {
    return <AppShell staff={staff} active="/billing"><div className="alert warn">Billing is not set up in the database yet. In Supabase → SQL Editor run <b>supabase/migrations/0018_billing.sql</b>, then refresh this page.</div></AppShell>;
  }
  const images = await billingImageUrls({ ...s, show_seal: true });
  const letterhead = s.letterhead_path ? (await createAdminClient().storage.from("kmr-billing").createSignedUrl(s.letterhead_path, 3600)).data?.signedUrl ?? null : null;
  const qs = quotes ?? [];
  const open = qs.filter((q) => q.status === "sent"), won = qs.filter((q) => q.status === "accepted");
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
    <AppShell staff={staff} active={tab === "quotes" ? "/billing?tab=quotes" : "/billing"}>
      <div className="pagehead"><div><h1>Prices &amp; invoices</h1><p>Quotations with detailed costing (PDF on your letterhead), invoices, the price list and costing catalogue, and seller details.</p></div>
        <a className="btn" href={p("/quotes/new")}>+ New quotation</a></div>

      <nav className="tabs" style={{ marginTop: 6 }}>{TABS.map(([k, l]) => <a key={k} href={p(`/billing?tab=${k}`)} className={tab === k ? "active" : ""}>{l}</a>)}</nav>

      <div className="grid four">
        <div className="card stat"><div className="label">Waiting for payment</div><div className="value" style={{ fontSize: 20 }}>{sum(due)}</div><div className="hint">{due.length} issued invoice{due.length === 1 ? "" : "s"}</div></div>
        <div className="card stat"><div className="label">Overdue</div><div className="value" style={{ fontSize: 20, color: overdue.length ? "var(--danger)" : undefined }}>{overdue.length ? sum(overdue) : "None"}</div><div className="hint">Past the due date</div></div>
        <div className="card stat"><div className="label">Paid this month</div><div className="value" style={{ fontSize: 20, color: "var(--ok)" }}>{sum(inv.filter((i) => i.status === "paid" && (i.issue_date ?? "").slice(0, 7) === month))}</div><div className="hint">Invoices dated this month</div></div>
        <div className="card stat"><div className="label">Payments to verify</div><div className="value" style={{ fontSize: 20, color: toVerify.size ? "var(--warn)" : undefined }}>{toVerify.size || "None"}</div>
          <div className="hint">{toVerify.size ? "Customers reported a payment — check your bank statement" : s.bank_account_no ? `Paid into ${s.bank_name ?? "bank"} a/c …${String(s.bank_account_no).slice(-4)}` : "Add your bank account below"}</div></div>
      </div>

      {tab === "quotes" && <>
      <div className="grid four" style={{ marginTop: 16 }}>
        <div className="card stat"><div className="label">Quotations sent</div><div className="value" style={{ fontSize: 20 }}>{open.length}</div><div className="hint">{open.length ? `Worth ${inr(open.reduce((a, q) => a + Number(q.total), 0))} incl. GST` : "Waiting for an answer"}</div></div>
        <div className="card stat"><div className="label">Accepted</div><div className="value" style={{ fontSize: 20, color: "var(--ok)" }}>{won.length}</div><div className="hint">{won.length ? inr(won.reduce((a, q) => a + Number(q.total), 0)) : "None yet"}</div></div>
        <div className="card stat"><div className="label">Drafts</div><div className="value" style={{ fontSize: 20 }}>{qs.filter((q) => q.status === "draft").length}</div><div className="hint">Not sent yet</div></div>
        <div className="card stat"><div className="label">Win rate</div><div className="value" style={{ fontSize: 20 }}>{won.length + qs.filter((q) => q.status === "declined").length ? Math.round(won.length / (won.length + qs.filter((q) => q.status === "declined").length) * 100) + "%" : "—"}</div><div className="hint">Accepted ÷ decided</div></div>
      </div>
      <div className="card">
        <div className="spread"><h2>Quotations</h2><a className="btn small" href={p("/quotes/new")}>+ New quotation</a></div>
        {qs.length ? (
          <div className="tablewrap"><table>
            <thead><tr><th>Quotation</th><th>To</th><th>Subject</th><th>Date</th><th>Valid until</th><th style={{ textAlign: "right" }}>Total (incl. GST)</th><th>Status</th><th /></tr></thead>
            <tbody>{qs.map((q) => {
              const lapsed = q.status === "sent" && q.valid_until && q.valid_until < today;
              return (
                <tr key={q.id}>
                  <td><a className="mono" href={p(`/quotes/${q.id}`)}><b>{q.number ?? "Draft"}</b></a></td>
                  <td>{q.to_name}</td><td><small>{q.subject}</small></td>
                  <td>{fmtDate(q.quote_date)}</td><td>{fmtDate(q.valid_until)}</td>
                  <td style={{ textAlign: "right", whiteSpace: "nowrap" }}><b>{inr(q.total)}</b></td>
                  <td><span className={`badge ${lapsed ? "warn" : QUOTE_TONE[q.status]}`}>{lapsed ? "lapsed" : q.status}</span></td>
                  <td style={{ whiteSpace: "nowrap" }}><a className="btn secondary small" href={p(`/api/quotes/${q.id}/pdf`)} target="_blank" rel="noopener">PDF</a></td>
                </tr>);
            })}</tbody>
          </table></div>
        ) : <Empty>No quotations yet. Use <b>+ New quotation</b> — pick the customer, the apps and the costing items, and download the PDF on your letterhead.</Empty>}
      </div>
      {manager && (
        <div className="card">
          <h2>Quotation defaults</h2>
          <p className="muted" style={{ marginTop: -4 }}>Filled into every new quotation; each quotation can still be changed.</p>
          <ActionForm action={saveQuoteSettings} submitLabel="Save defaults" className="formgrid">
            <label className="field">Number prefix<input name="quote_prefix" defaultValue={s.quote_prefix ?? "KMR/QT"} required /><span className="help">Numbers like {s.quote_prefix ?? "KMR/QT"}/{today.slice(0, 4)}/001</span></label>
            <label className="field">Valid for (days)<input name="quote_validity_days" type="number" min={1} max={180} defaultValue={s.quote_validity_days ?? 30} required /></label>
            <label className="field full">What the subscription includes — one per line<textarea name="quote_includes" rows={5} defaultValue={s.quote_includes ?? ""} /></label>
            <label className="field full">Terms &amp; conditions — one per line<textarea name="quote_terms" rows={8} defaultValue={s.quote_terms ?? ""} /></label>
          </ActionForm>
        </div>
      )}
      </>}

      {tab === "invoices" && <div className="card" style={{ marginTop: 16 }}>
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
      </div>}

      {tab === "costing" && <>
      <div className="card" style={{ marginTop: 16 }}>
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
        <h2>Costing catalogue</h2>
        <p className="muted" style={{ marginTop: -4 }}>Everything a quotation is built from besides the per-user subscription: implementation, data migration, training, customisation days, on-site visits, AMC, devices, labels… Items marked <b>auto</b> are added when their app (or any app, for general items) is quoted. All amounts before GST.</p>
        {(costs as Cost[] | null)?.length ? (
          <div className="tablewrap"><table>
            <thead><tr><th>Item</th><th>For</th><th>Basis</th><th style={{ textAlign: "right" }}>Rate</th><th style={{ textAlign: "right" }}>Default qty</th><th>Auto</th><th>Status</th>{manager && <th />}</tr></thead>
            <tbody>{(costs as Cost[]).map((c) => (
              <tr key={c.id}>
                <td><b>{c.name}</b>{c.detail && <><br /><small className="muted">{c.detail}</small></>}</td>
                <td>{c.product_code ? prodName[c.product_code] ?? c.product_code : <span className="muted">Any app</span>}</td>
                <td>{BASIS[c.basis]?.label ?? c.basis}</td>
                <td style={{ textAlign: "right", whiteSpace: "nowrap" }}>{inr(c.amount)}</td>
                <td style={{ textAlign: "right" }}>{c.default_qty}</td>
                <td>{c.include_by_default ? <span className="badge ok">auto</span> : "—"}</td>
                <td><span className={`badge ${c.active ? "ok" : ""}`}>{c.active ? "in use" : "paused"}</span></td>
                {manager && <td style={{ whiteSpace: "nowrap", textAlign: "right" }}>
                  <details style={{ display: "inline-block" }}><summary className="btn secondary small">Edit</summary>
                    <div className="editpop">
                      <CostForm c={c} products={products ?? []} />
                    </div></details>
                  <form action={deleteCostItem} style={{ display: "inline" }}><input type="hidden" name="id" value={c.id} /><button className="btn ghost small">Remove</button></form>
                </td>}
              </tr>))}</tbody>
          </table></div>
        ) : <Empty>No cost items yet.</Empty>}
        {manager && <div style={{ marginTop: 16, paddingTop: 14, borderTop: "1px solid var(--border)" }}><h3>Add a cost item</h3><CostForm products={products ?? []} /></div>}
      </div>
      </>}

      {tab === "seller" && <>
      <div className="card" style={{ marginTop: 16 }}>
        <h2>Letterhead for quotations</h2>
        <p className="muted" style={{ marginTop: -4 }}>Every quotation PDF is printed on this A4 letterhead (portrait PNG or JPG, under 5 MB). The text is placed between the header line and the footer artwork. Without an upload the built-in KMR letterhead is used.</p>
        <div className="row" style={{ alignItems: "flex-start", gap: 16 }}>
          <div style={{ width: 150, aspectRatio: "210 / 297", border: "1px solid var(--border)", borderRadius: 8, overflow: "hidden", background: "#fff", display: "grid", placeItems: "center" }}>
            {letterhead ? <img src={letterhead} alt="" style={{ width: "100%", height: "100%", objectFit: "cover" }} /> : <small className="muted" style={{ padding: 8, textAlign: "center" }}>Built-in KMR letterhead</small>}
          </div>
          {manager && <div>
            <ActionForm action={uploadBillingImage} submitLabel={letterhead ? "Replace letterhead" : "Upload letterhead"} variant="secondary" hidden={{ kind: "letterhead" }}>
              <input type="file" name="image" accept="image/png,image/jpeg" required />
            </ActionForm>
            {letterhead && <form action={removeBillingImage} style={{ marginTop: 6 }}><input type="hidden" name="kind" value="letterhead" /><button className="linkbtn">Use the built-in letterhead</button></form>}
          </div>}
        </div>
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
      </>}
    </AppShell>
  );
}

function CostForm({ c, products }: { c?: Cost; products: { code: string; name: string }[] }) {
  return (
    <ActionForm action={saveCostItem} submitLabel={c ? "Save item" : "Add item"} className="formgrid" hidden={c ? { id: c.id } : undefined} resetOnSuccess={!c}>
      <label className="field">Name<input name="name" defaultValue={c?.name ?? ""} required placeholder="e.g. Implementation & configuration" /></label>
      <label className="field">For app<select name="product_code" defaultValue={c?.product_code ?? ""}><option value="">Any app / general</option>{products.map((x) => <option key={x.code} value={x.code}>{x.name}</option>)}</select></label>
      <label className="field">Basis<select name="basis" defaultValue={c?.basis ?? "one_time"}>{Object.entries(BASIS).map(([k, b]) => <option key={k} value={k}>{b.label}</option>)}</select></label>
      <label className="field">Rate (₹, before GST)<input name="amount" inputMode="decimal" defaultValue={c ? String(c.amount) : ""} required /></label>
      <label className="field">Default quantity<input name="default_qty" inputMode="decimal" defaultValue={c ? String(c.default_qty) : "1"} /></label>
      <label className="field">Order<input name="sort_order" type="number" defaultValue={c?.sort_order ?? 100} /></label>
      <label className="field">Status<select name="active" defaultValue={c?.active === false ? "off" : "on"}><option value="on">In use</option><option value="off">Paused</option></select></label>
      <label className="field checkline"><input type="checkbox" name="include_by_default" defaultChecked={!!c?.include_by_default} /> Add automatically when the app is quoted</label>
      <label className="field full">Detail (printed under the line)<input name="detail" defaultValue={c?.detail ?? ""} /></label>
    </ActionForm>
  );
}
