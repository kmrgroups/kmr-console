import { amountInWords, fmtMoney } from "@/lib/money";
import { fmtDate } from "@/components/ui";

export type Party = Record<string, string | null | undefined>;
export interface InvoiceData {
  number: string | null; status: string; currency: string; issue_date: string | null; due_date: string | null;
  tax_type: string; gst_rate: number | string; subtotal: number | string; cgst: number | string; sgst: number | string; igst: number | string; total: number | string;
  notes: string | null; cancelled_reason: string | null; paid_at: string | null; created_at: string;
}
export interface LineData { id: number; description: string; period_from: string | null; period_to: string | null; qty: number | string; unit_amount: number | string; amount: number | string; product_code: string | null }

const num = (v: number | string) => Number(v);
const addr = (p: Party) => [p.address, [p.city, p.state, p.postal_code].filter(Boolean).join(", ")].filter(Boolean);

/** A4 invoice, printable (Print / Save as PDF). Draft invoices show the live seller and buyer details. */
export function InvoiceDoc({ inv, lines, seller, buyer, logoUrl }: { inv: InvoiceData; lines: LineData[]; seller: Party; buyer: Party; logoUrl?: string | null }) {
  const taxed = inv.tax_type === "cgst_sgst" || inv.tax_type === "igst";
  const title = seller.gstin ? "Tax Invoice" : "Invoice";
  const half = num(inv.gst_rate) / 2;
  const hasBank = Boolean(seller.bank_account_no || seller.bank_ifsc);
  const stamp = inv.status === "draft" ? "Draft" : inv.status === "cancelled" ? "Cancelled" : inv.status === "paid" ? "Paid" : null;
  return (
    <article className="invoice">
      {stamp && <div className={`invoice-stamp ${inv.status}`}>{stamp}</div>}
      <header className="invoice-head">
        <div>
          {logoUrl && <img src={logoUrl} alt="" className="invoice-logo" />}
          <div className="invoice-seller">{seller.legal_name}</div>
          {addr(seller).map((l, i) => <div key={i}>{l}</div>)}
          {seller.gstin && <div>GSTIN <b className="mono">{seller.gstin}</b>{seller.state_code ? <> · State code {seller.state_code}</> : null}</div>}
          {seller.pan && <div>PAN <span className="mono">{seller.pan}</span></div>}
          {(seller.email || seller.phone) && <div>{[seller.email, seller.phone].filter(Boolean).join(" · ")}</div>}
        </div>
        <div className="invoice-meta">
          <h2>{title}</h2>
          <table><tbody>
            <tr><th>Invoice no.</th><td className="mono">{inv.number ?? "— (given when issued)"}</td></tr>
            <tr><th>Date</th><td>{fmtDate(inv.issue_date ?? inv.created_at.slice(0, 10))}</td></tr>
            {inv.due_date && <tr><th>Due by</th><td>{fmtDate(inv.due_date)}</td></tr>}
            <tr><th>Currency</th><td>{inv.currency}</td></tr>
          </tbody></table>
        </div>
      </header>

      <section className="invoice-parties">
        <div>
          <div className="invoice-label">Bill to</div>
          <b>{buyer.name}</b>{buyer.code && <span className="muted mono"> · {buyer.code}</span>}
          {addr(buyer).map((l, i) => <div key={i}>{l}</div>)}
          {buyer.country && buyer.country !== "IN" && <div>{buyer.country}</div>}
          {buyer.tax_id && <div>{buyer.country === "IN" || !buyer.country ? "GSTIN" : "Tax ID"} <span className="mono">{buyer.tax_id}</span></div>}
          {buyer.contact_name && <div>Attn: {buyer.contact_name}{buyer.contact_email ? ` · ${buyer.contact_email}` : ""}</div>}
        </div>
        <div>
          <div className="invoice-label">Place of supply</div>
          {inv.tax_type === "export" ? <>Outside India ({buyer.country})</> : <>{buyer.state || seller.state || "—"}{buyer.tax_id && /^\d{2}/.test(buyer.tax_id) ? ` (${buyer.tax_id.slice(0, 2)})` : ""}</>}
          <div className="invoice-label" style={{ marginTop: 8 }}>SAC</div>
          <span className="mono">{seller.sac_code || "998314"}</span> — IT software services
        </div>
      </section>

      <div className="invoice-scroll"><table className="invoice-lines">
        <thead><tr><th style={{ width: 32 }}>#</th><th>Description</th><th className="num">Qty</th><th className="num">Rate</th><th className="num">Amount</th></tr></thead>
        <tbody>
          {lines.map((l, i) => (
            <tr key={l.id}>
              <td>{i + 1}</td>
              <td>{l.description}{l.period_from && l.period_to && <div className="muted" style={{ fontSize: 12.5 }}>Period {fmtDate(l.period_from)} – {fmtDate(l.period_to)}</div>}</td>
              <td className="num">{num(l.qty).toLocaleString("en-IN")}</td>
              <td className="num">{fmtMoney(l.unit_amount, inv.currency)}</td>
              <td className="num">{fmtMoney(l.amount, inv.currency)}</td>
            </tr>
          ))}
        </tbody>
      </table></div>

      <section className="invoice-bottom">
        <div className="invoice-words">
          <div className="invoice-label">Amount in words</div>
          <div>{amountInWords(inv.total, inv.currency)}</div>
          {inv.tax_type === "export" && <p className="invoice-note">Supply meant for export of services under LUT{seller.lut_no ? ` (${seller.lut_no})` : ""} without payment of integrated tax (IGST).</p>}
          {!seller.gstin && <p className="invoice-note">GST not charged.</p>}
          {inv.notes && <p className="invoice-note">{inv.notes}</p>}
        </div>
        <table className="invoice-totals"><tbody>
          <tr><th>Taxable value</th><td>{fmtMoney(inv.subtotal, inv.currency)}</td></tr>
          {inv.tax_type === "cgst_sgst" && <><tr><th>CGST {half}%</th><td>{fmtMoney(inv.cgst, inv.currency)}</td></tr><tr><th>SGST {half}%</th><td>{fmtMoney(inv.sgst, inv.currency)}</td></tr></>}
          {inv.tax_type === "igst" && <tr><th>IGST {num(inv.gst_rate)}%</th><td>{fmtMoney(inv.igst, inv.currency)}</td></tr>}
          {inv.tax_type === "export" && <tr><th>IGST (export, LUT)</th><td>{fmtMoney(0, inv.currency)}</td></tr>}
          <tr className="grand"><th>Total</th><td>{fmtMoney(inv.total, inv.currency)}</td></tr>
        </tbody></table>
      </section>

      {inv.status === "cancelled" && inv.cancelled_reason && <p className="invoice-note">Cancelled: {inv.cancelled_reason}</p>}
      {(hasBank || seller.bank_details || seller.upi_id || seller.terms) && (
        <section className="invoice-pay">
          {(hasBank || seller.bank_details || seller.upi_id) && <div><div className="invoice-label">Pay to</div>
            {hasBank && <table className="invoice-bank"><tbody>
              {seller.bank_account_name && <tr><th>Account name</th><td>{seller.bank_account_name}</td></tr>}
              {seller.bank_account_no && <tr><th>Account no.</th><td className="mono">{seller.bank_account_no}</td></tr>}
              {seller.bank_ifsc && <tr><th>IFSC</th><td className="mono">{seller.bank_ifsc}</td></tr>}
              {(seller.bank_name || seller.bank_branch) && <tr><th>Bank</th><td>{[seller.bank_name, seller.bank_branch].filter(Boolean).join(", ")}</td></tr>}
              {seller.bank_account_type && <tr><th>Type</th><td>{seller.bank_account_type}</td></tr>}
              {seller.bank_swift && inv.tax_type === "export" && <tr><th>SWIFT</th><td className="mono">{seller.bank_swift}</td></tr>}
            </tbody></table>}
            {seller.upi_id && <div>UPI <span className="mono">{seller.upi_id}</span></div>}
            {seller.bank_details && <div style={{ whiteSpace: "pre-line" }}>{seller.bank_details}</div>}
            <div className="muted" style={{ marginTop: 4 }}>Please quote invoice {inv.number ?? "number"} in the remarks.</div></div>}
          {seller.terms && <div><div className="invoice-label">Terms</div><div style={{ whiteSpace: "pre-line" }}>{seller.terms}</div></div>}
        </section>
      )}
      <footer className="invoice-foot">
        {taxed || seller.gstin ? "This is a computer-generated invoice and needs no signature." : "This is a computer-generated invoice."}
        <span>For {seller.legal_name}</span>
      </footer>
    </article>
  );
}
