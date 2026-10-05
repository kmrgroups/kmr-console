import "server-only";
import { LetterheadDoc, NAVY, INK, X0, X1, WHITE, GOLD, fmtDateLong, type SignArt } from "@/lib/letterhead-pdf";
import { basisText, inr, inWords, lineAmount, type QuoteLine, type ScopeRow } from "@/lib/quote";

export type QuoteDoc = {
  number: string | null; quote_date: string; valid_until: string | null; currency: string; status?: string;
  to_name: string; to_attn?: string | null; to_address?: string | null; to_gstin?: string | null; to_email?: string | null; to_phone?: string | null;
  subject: string; intro?: string | null; scope: ScopeRow[]; lines: QuoteLine[]; includes?: string | null; terms?: string | null;
  discount_pct: number; gst_rate: number; subtotal: number; discount: number; taxable: number; gst: number; total: number;
  seller: { trade_name?: string | null; legal_name?: string | null; gstin?: string | null; signatory_name?: string | null; signatory_title?: string | null };
  seat_label?: (code?: string | null) => string;
};

/** Quotation on the letterhead; drafts carry a DRAFT watermark (with the seal and signature, like invoices). */
export async function quotePdf(q: QuoteDoc, letterhead?: Uint8Array | null, art?: SignArt): Promise<Uint8Array> {
  const company = q.seller.trade_name || "KMR Group of Companies";
  const draft = !q.status || q.status === "draft";
  const d = await LetterheadDoc.create({ title: `Quotation ${q.number ?? ""} — ${q.to_name}`, author: company }, letterhead);
  d.title("QUOTATION");
  d.refBox([["Quotation No.", q.number ?? "Draft"], ["Date", fmtDateLong(q.quote_date)], ["Valid until", fmtDateLong(q.valid_until)], ["Currency", q.currency === "INR" ? "INR (₹)" : q.currency]]);

  d.label("To"); d.para(`M/s. ${q.to_name}`, d.bold, 11, NAVY, 1);
  [q.to_attn && `Attn: ${q.to_attn}`, q.to_address, [q.to_gstin && `GSTIN: ${q.to_gstin}`, q.to_email, q.to_phone].filter(Boolean).join("   ·   ")]
    .filter(Boolean).forEach((l) => d.para(String(l), d.reg, 9, INK, 0));
  d.y -= 8;

  const subj = d.wrap(`SUBJECT: ${q.subject}`, d.bold, 9.6, X1 - X0 - 20), sh = subj.length * 13 + 12;
  d.ensure(sh + 2);
  d.page.drawRectangle({ x: X0, y: d.y - sh, width: X1 - X0, height: sh, color: NAVY });
  d.page.drawRectangle({ x: X0, y: d.y - sh, width: 4, height: sh, color: GOLD });
  subj.forEach((l, i) => d.text(l, X0 + 12, d.y - 16 - i * 13, d.bold, 9.6, WHITE));
  d.y -= sh + 12;

  d.para("Dear Sir / Madam,", d.reg, 9.4, INK, 2);
  if (q.intro) d.para(q.intro, d.reg, 9.2, INK, 8);

  let n = 1;
  if (q.scope.length) {
    d.heading(`${n++}. SCOPE OF SUPPLY`);
    d.table([{ title: "#", w: 5, align: "center" }, { title: "MODULE", w: 30 }, { title: "INCLUDED CAPABILITY", w: 65 }],
      q.scope.map((s, i) => ({ cells: [String(i + 1), s.module, s.capability], bold: true })), { zebra: true });
    d.y -= 10;
  }
  d.heading(`${n++}. COMMERCIAL PROPOSAL`);
  const seat = (c?: string | null) => (q.seat_label ? q.seat_label(c) : "users");
  d.table([{ title: "#", w: 5, align: "center" }, { title: "PARTICULARS", w: 43 }, { title: "BASIS", w: 20 }, { title: "RATE (₹)", w: 15, align: "right" }, { title: "AMOUNT (₹)", w: 17, align: "right" }],
    q.lines.map((l, i) => ({ cells: [String(i + 1), l.particulars, basisText(l, seat(l.product_code)), inr(l.rate, false), inr(lineAmount(l), false)], bold: true, sub: l.detail || undefined })), { zebra: true });
  const tot: [string, string][] = [["Sub-total", inr(q.subtotal, false)]];
  if (q.discount > 0) tot.push([`Less: discount @ ${q.discount_pct}%`, `− ${inr(q.discount, false)}`], ["Total before GST", inr(q.taxable, false)]);
  tot.push([`GST @ ${q.gst_rate}%`, inr(q.gst, false)]);
  d.totals(tot, ["GRAND TOTAL", `₹ ${inr(q.total, false)}`]);
  d.para(`Amount in words: ${inWords(q.total)}`, d.med, 8.6, NAVY, 10);

  const lines = (t?: string | null) => (t ?? "").split("\n").map((s) => s.trim()).filter(Boolean);
  if (lines(q.includes).length) { d.heading(`${n++}. THE SUBSCRIPTION INCLUDES`); d.bullets(lines(q.includes)); d.y -= 6; }
  if (lines(q.terms).length) { d.heading(`${n++}. COMMERCIAL TERMS & CONDITIONS`); d.bullets(lines(q.terms), true); d.y -= 6; }

  await d.signBlock({ company, name: q.seller.signatory_name, title: q.seller.signatory_title, art, acceptance: true });
  return d.finish({ ref: q.number ?? "Draft quotation", note: "Confidential commercial proposal", watermark: draft ? "DRAFT" : null });
}
