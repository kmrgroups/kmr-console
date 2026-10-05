import "server-only";
import { LetterheadDoc, NAVY, INK, MUTED, X0, X1, fmtDateLong, type SignArt } from "@/lib/letterhead-pdf";
import { amountInWords, fmtMoney } from "@/lib/money";
import type { InvoiceData, LineData, Party } from "@/components/InvoiceDoc";

/** GST invoice on the letterhead — drafts, issued, paid and cancelled alike (watermarked when not simply issued). */
export async function invoicePdf(inv: InvoiceData, lines: LineData[], seller: Party, buyer: Party, letterhead?: Uint8Array | null, art?: SignArt): Promise<Uint8Array> {
  const company = seller.trade_name || seller.legal_name || "KMR Group of Companies";
  const m = (v: number | string) => fmtMoney(v, inv.currency);
  const d = await LetterheadDoc.create({ title: `${seller.gstin ? "Tax Invoice" : "Invoice"} ${inv.number ?? "(draft)"} — ${buyer.name ?? ""}`, author: company }, letterhead);
  d.title(seller.gstin ? "TAX INVOICE" : "INVOICE");

  // the statutory line the letterhead does not carry
  const legal = seller.trade_name && seller.legal_name && seller.trade_name.toLowerCase() !== seller.legal_name.toLowerCase()
    ? `${seller.constitution === "Proprietorship" ? "Prop." : "Legal name:"} ${seller.legal_name}` : "";
  const stat = [legal, seller.gstin && `GSTIN ${seller.gstin}${seller.state_code ? ` (State code ${seller.state_code})` : ""}`, seller.pan && `PAN ${seller.pan}`,
    seller.udyam_no && `Udyam ${seller.udyam_no}${seller.msme_category ? ` · ${seller.msme_category}` : ""}`].filter(Boolean).join("   ·   ");
  if (stat) { const ls = d.wrap(stat, d.reg, 7.8, X1 - X0); ls.forEach((l) => { d.text(l, (595.28 - d.width(l, d.reg, 7.8)) / 2, d.y - 4, d.reg, 7.8, MUTED); d.y -= 11; }); d.y -= 8; }

  d.refBox([["Invoice No.", inv.number ?? "Draft"], ["Invoice date", fmtDateLong(inv.issue_date ?? inv.created_at)], ["Due by", fmtDateLong(inv.due_date)], ["Currency", inv.currency]]);

  // bill to (left) · place of supply + SAC (right)
  const top = d.y, half = (X1 - X0) / 2;
  d.label("Bill to"); d.para(String(buyer.name ?? ""), d.bold, 10.5, NAVY, 1);
  const addr = [buyer.address, [buyer.city, buyer.state, buyer.postal_code].filter(Boolean).join(", "), buyer.country && buyer.country !== "IN" ? buyer.country : "",
    buyer.tax_id && `${buyer.country === "IN" || !buyer.country ? "GSTIN" : "Tax ID"}: ${buyer.tax_id}`, buyer.contact_name && `Attn: ${buyer.contact_name}${buyer.contact_email ? ` · ${buyer.contact_email}` : ""}`].filter(Boolean) as string[];
  addr.forEach((l) => d.wrap(l, d.reg, 8.8, half - 10).forEach((x) => { d.text(x, X0, d.y - 9, d.reg, 8.8); d.y -= 12; }));
  const leftEnd = d.y; d.y = top;
  const rx = X0 + half + 10;
  const pos = inv.tax_type === "export" ? `Outside India (${buyer.country ?? ""})` : `${buyer.state || seller.state || "—"}${buyer.tax_id && /^\d{2}/.test(String(buyer.tax_id)) ? ` (${String(buyer.tax_id).slice(0, 2)})` : ""}`;
  d.text("PLACE OF SUPPLY", rx, d.y - 8, d.bold, 7.2, NAVY); d.text(pos, rx, d.y - 21, d.reg, 9); 
  d.text("SAC", rx, d.y - 38, d.bold, 7.2, NAVY); d.text(`${seller.sac_code || "998314"} — IT software services`, rx, d.y - 51, d.reg, 9);
  d.y = Math.min(leftEnd, d.y - 58) - 8;

  d.table([{ title: "#", w: 5, align: "center" }, { title: "DESCRIPTION", w: 51 }, { title: "QTY", w: 9, align: "right" }, { title: "RATE", w: 16, align: "right" }, { title: "AMOUNT", w: 19, align: "right" }],
    lines.map((l, i) => ({ cells: [String(i + 1), l.description, Number(l.qty).toLocaleString("en-IN"), m(l.unit_amount), m(l.amount)], bold: true,
      sub: l.period_from && l.period_to ? `Period ${fmtDateLong(l.period_from)} – ${fmtDateLong(l.period_to)}` : undefined })), { zebra: true });
  d.y -= 6;

  const half2 = Number(inv.gst_rate) / 2;
  const tot: [string, string][] = [["Taxable value", m(inv.subtotal)]];
  if (inv.tax_type === "cgst_sgst") tot.push([`CGST ${half2}%`, m(inv.cgst)], [`SGST ${half2}%`, m(inv.sgst)]);
  if (inv.tax_type === "igst") tot.push([`IGST ${Number(inv.gst_rate)}%`, m(inv.igst)]);
  if (inv.tax_type === "export") tot.push(["IGST (export under LUT)", m(0)]);
  d.totals(tot, ["TOTAL", m(inv.total)]);
  d.para(`Amount in words: ${amountInWords(inv.total, inv.currency)}`, d.med, 8.6, NAVY, 6);
  const notes = [
    inv.tax_type === "export" && `Supply meant for export of services under LUT${seller.lut_no ? ` (${seller.lut_no})` : ""} without payment of integrated tax (IGST).`,
    !seller.gstin && "GST not charged.",
    seller.udyam_no && (seller.show_msme_note as unknown) !== false && `${seller.msme_category ? `${seller.msme_category} enterprise` : "Enterprise"} registered under the MSMED Act, 2006 (Udyam ${seller.udyam_no}). Payment is due within the agreed period, not exceeding 45 days from acceptance (Section 15).`,
    inv.notes, inv.status === "cancelled" && inv.cancelled_reason && `Cancelled: ${inv.cancelled_reason}`,
  ].filter(Boolean) as string[];
  notes.forEach((t) => d.para(t, d.reg, 8, MUTED, 2));

  // pay to + terms
  const bank: [string, string][] = ([["Account name", seller.bank_account_name], ["Account no.", seller.bank_account_no], ["IFSC", seller.bank_ifsc],
    ["Bank", [seller.bank_name, seller.bank_branch].filter(Boolean).join(", ")], ["Type", seller.bank_account_type], ["UPI", seller.upi_id],
    ...(inv.tax_type === "export" ? [["SWIFT", seller.bank_swift]] : [])] as [string, string | null | undefined][]).filter(([, v]) => v) as [string, string][];
  if (bank.length || seller.terms) {
    d.ensure(40); d.y -= 4;
    if (bank.length) { d.label("Pay to"); d.kv(bank, X0, X1 - X0); d.para(`Please quote invoice ${inv.number ?? "number"} in the payment remarks.`, d.reg, 8, MUTED, 4); }
    if (seller.bank_details) d.para(String(seller.bank_details), d.reg, 8.4, INK, 4);
    if (seller.terms) { d.label("Terms"); d.para(String(seller.terms), d.reg, 8.4, INK, 4); }
  }

  const draft = inv.status === "draft";
  await d.signBlock({ company, name: seller.signatory_name, title: seller.signatory_title, art: draft ? undefined : art,
    left: art?.seal || art?.signature ? "This is a computer-generated invoice." : "This is a computer-generated invoice and needs no signature." });
  return d.finish({ ref: inv.number ?? "Draft invoice", note: draft ? "Draft — not valid as a tax invoice until issued" : "Original for recipient",
    watermark: draft ? "DRAFT" : inv.status === "cancelled" ? "CANCELLED" : inv.status === "paid" ? "PAID" : null,
    watermarkColor: inv.status === "cancelled" ? "red" : inv.status === "paid" ? "green" : "muted" });
}
