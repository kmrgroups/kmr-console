import { notFound } from "next/navigation";
import { createAdminClient } from "@/lib/supabase/admin";
import { InvoiceDoc, type InvoiceData, type LineData, type Party } from "@/components/InvoiceDoc";
import { PayButton } from "@/components/PayButton";
import { PrintButton } from "@/components/PrintButton";
import { fmtDate } from "@/components/ui";
import { fmtMoney } from "@/lib/money";
import { razorpay } from "@/lib/razorpay";
import { platformBrand } from "@/lib/brand";

export const metadata = { title: "Invoice" };
export const dynamic = "force-dynamic";

type Found = { invoice: InvoiceData & { seller: Party; buyer: Party; pay_token: string }; lines: LineData[]; paid_by: { provider: string; mode: string; payment_id: string | null; reference: string | null; paid_at: string } | null };

/** Public page behind each invoice's pay link: the invoice, and a Pay button while it is unpaid. */
export default async function PayPage({ params }: { params: Promise<{ token: string }> }) {
  const { token } = await params;
  if (!/^[a-f0-9]{20,64}$/.test(token)) notFound();
  const { data } = await createAdminClient().rpc("invoice_for_token", { p_token: token });
  if (!data) notFound();
  const { invoice: inv, lines, paid_by } = data as Found;
  const brand = await platformBrand();
  const today = new Date().toISOString().slice(0, 10);

  return (
    <div className="paywrap">
      <div className="paybar">
        <div>
          <div className="muted" style={{ fontSize: 13 }}>{inv.seller.legal_name} · Invoice <span className="mono">{inv.number}</span></div>
          <div style={{ fontSize: 22, fontWeight: 700 }}>{fmtMoney(inv.total, inv.currency)}</div>
          <div style={{ fontSize: 13 }}>
            {inv.status === "paid" && <span className="badge ok">Paid {fmtDate(paid_by?.paid_at ?? inv.paid_at)}{paid_by?.payment_id ? ` · ${paid_by.payment_id}` : ""}</span>}
            {inv.status === "cancelled" && <span className="badge danger">Cancelled — nothing to pay</span>}
            {inv.status === "issued" && <span className={`badge ${inv.due_date && inv.due_date < today ? "danger" : "info"}`}>Due {fmtDate(inv.due_date)}</span>}
          </div>
        </div>
        <div className="row" style={{ alignItems: "flex-start" }}>
          <PrintButton label={inv.status === "paid" ? "Print / save receipt" : "Print / Save as PDF"} />
          {inv.status === "issued" && (razorpay.configured
            ? <PayButton token={inv.pay_token} label={`Pay ${fmtMoney(inv.total, inv.currency)}`} test={razorpay.mode === "test"} />
            : <div className="muted" style={{ fontSize: 13, maxWidth: 260 }}>Pay by bank transfer or UPI using the details on the invoice, quoting the invoice number.</div>)}
        </div>
      </div>
      <InvoiceDoc inv={inv} lines={lines} seller={inv.seller} buyer={inv.buyer} logoUrl={brand.logo_url} />
    </div>
  );
}
