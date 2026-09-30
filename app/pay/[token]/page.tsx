import { notFound } from "next/navigation";
import QRCode from "qrcode";
import { createAdminClient } from "@/lib/supabase/admin";
import { InvoiceDoc, type InvoiceData, type LineData, type Party } from "@/components/InvoiceDoc";
import { PrintButton } from "@/components/PrintButton";
import { CopyValue, ReportPaymentForm } from "@/components/PayActions";
import { fmtDate } from "@/components/ui";
import { fmtMoney } from "@/lib/money";
import { platformBrand } from "@/lib/brand";
import { billingImageUrls } from "@/lib/billing-files";

export const metadata = { title: "Invoice" };
export const dynamic = "force-dynamic";

type Reported = { method: string; reference: string; amount: number; paid_on: string; status: string; reject_reason: string | null; created_at: string };
type Found = {
  invoice: InvoiceData & { seller: Party; buyer: Party; pay_token: string };
  lines: LineData[];
  paid_by: { method: string | null; reference: string | null; paid_at: string } | null;
  reported?: Reported[];
};
const METHOD: Record<string, string> = { neft: "NEFT", rtgs: "RTGS", imps: "IMPS", upi: "UPI", cheque: "Cheque", other: "Other" };

/** Public page behind each invoice's pay link: how to pay (bank account, UPI QR), "I've paid", and the invoice. */
export default async function PayPage({ params }: { params: Promise<{ token: string }> }) {
  const { token } = await params;
  if (!/^[a-f0-9]{20,64}$/.test(token)) notFound();
  const { data } = await createAdminClient().rpc("invoice_for_token", { p_token: token });
  if (!data) notFound();
  const { invoice: inv, lines, paid_by, reported = [] } = data as Found;
  const s = inv.seller;
  const [brand, images] = await Promise.all([platformBrand(), billingImageUrls(s)]);
  const today = new Date().toISOString().slice(0, 10);
  const total = Number(inv.total).toFixed(2);
  const waiting = reported.filter((r) => r.status === "reported");

  // UPI QR with the payee, exact amount and the invoice number filled in (INR only)
  let qr: string | null = null;
  if (inv.status === "issued" && inv.currency === "INR" && s.upi_id) {
    const upi = `upi://pay?pa=${encodeURIComponent(s.upi_id)}&pn=${encodeURIComponent(s.bank_account_name || s.trade_name || s.legal_name || "KMR")}&am=${total}&cu=INR&tn=${encodeURIComponent(`Invoice ${inv.number}`)}`;
    qr = await QRCode.toString(upi, { type: "svg", margin: 1, width: 180, errorCorrectionLevel: "M" });
  }
  const rows: [string, string | null | undefined, boolean?][] = [
    ["Account name", s.bank_account_name], ["Account number", s.bank_account_no, true], ["IFSC", s.bank_ifsc, true],
    ["Bank", [s.bank_name, s.bank_branch].filter(Boolean).join(", ")], ["Account type", s.bank_account_type],
    ...(inv.currency !== "INR" ? [["SWIFT", s.bank_swift, true] as [string, string | null | undefined, boolean]] : []),
    ["Amount", fmtMoney(inv.total, inv.currency)], ["Remarks / reference", `Invoice ${inv.number}`, true],
  ];

  return (
    <div className="paywrap">
      <div className="paybar">
        <div>
          <div className="muted" style={{ fontSize: 13 }}>{s.trade_name || s.legal_name} · Invoice <span className="mono">{inv.number}</span></div>
          <div style={{ fontSize: 22, fontWeight: 700 }}>{fmtMoney(inv.total, inv.currency)}</div>
          <div style={{ fontSize: 13 }}>
            {inv.status === "paid" && <span className="badge ok">Paid {fmtDate(paid_by?.paid_at ?? inv.paid_at)}{paid_by?.reference ? ` · ${paid_by.reference}` : ""}</span>}
            {inv.status === "cancelled" && <span className="badge danger">Cancelled — nothing to pay</span>}
            {inv.status === "issued" && (waiting.length
              ? <span className="badge warn">Payment reported — KMR is confirming it</span>
              : <span className={`badge ${inv.due_date && inv.due_date < today ? "danger" : "info"}`}>Due {fmtDate(inv.due_date)}</span>)}
          </div>
        </div>
        <PrintButton label={inv.status === "paid" ? "Print / save receipt" : "Print / Save as PDF"} />
      </div>

      {inv.status === "issued" && (
        <div className="card noprint" style={{ marginBottom: 16 }}>
          <h2>How to pay</h2>
          <div className="payhow">
            {s.bank_account_no && (
              <div>
                <div className="invoice-label">{inv.currency === "INR" ? "Bank transfer — NEFT / RTGS / IMPS" : "International wire transfer"}</div>
                <table className="invoice-bank" style={{ fontSize: 14 }}><tbody>
                  {rows.filter(([, v]) => v).map(([k, v, copy]) => (
                    <tr key={k}><th style={{ fontSize: 13 }}>{k}</th><td style={{ fontSize: 14 }}><b className={copy ? "mono" : undefined}>{v}</b>{copy && <CopyValue value={String(v)} />}</td></tr>))}
                </tbody></table>
              </div>
            )}
            {qr && (
              <div style={{ textAlign: "center" }}>
                <div className="invoice-label">Scan with any UPI app</div>
                <div className="payqr" dangerouslySetInnerHTML={{ __html: qr }} />
                <div style={{ fontSize: 13 }}><span className="mono">{s.upi_id}</span><CopyValue value={String(s.upi_id)} /></div>
                <small className="muted">{fmtMoney(inv.total, inv.currency)} and the invoice number are filled in</small>
              </div>
            )}
          </div>
          {s.bank_details && <p className="muted" style={{ fontSize: 13, whiteSpace: "pre-line", marginTop: 10 }}>{s.bank_details}</p>}

          <div style={{ marginTop: 18, paddingTop: 14, borderTop: "1px solid var(--border)" }}>
            <h3>Already paid? Tell us</h3>
            <p className="muted" style={{ fontSize: 13, marginTop: -2 }}>Send the UTR / reference so we can match it in our bank statement. The invoice is marked paid once the money arrives.</p>
            <ReportPaymentForm token={inv.pay_token} amount={total} currency={inv.currency} />
          </div>
        </div>
      )}

      {reported.length > 0 && inv.status !== "cancelled" && (
        <div className="card noprint" style={{ marginBottom: 16 }}>
          <h3>Payments you reported</h3>
          <ul className="timeline">{reported.map((r, i) => (
            <li key={i}><span><b>{METHOD[r.method] ?? r.method}</b> · <span className="mono">{r.reference}</span> · {fmtMoney(r.amount, inv.currency)} · paid {fmtDate(r.paid_on)}
              <br />{r.status === "reported" ? <span className="badge warn">Waiting for KMR to confirm</span> : <span className="badge danger">Not confirmed: {r.reject_reason}</span>}</span>
              <small>{fmtDate(r.created_at)}</small></li>))}</ul>
        </div>
      )}

      <InvoiceDoc inv={inv} lines={lines} seller={s} buyer={inv.buyer} logoUrl={brand.logo_url} sealUrl={images.seal} signatureUrl={images.signature} />
    </div>
  );
}
