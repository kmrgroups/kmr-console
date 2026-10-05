import { NextResponse } from "next/server";
import { getStaff } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { quotePdf } from "@/lib/quote-pdf";
import { letterheadBytes, signArt } from "@/lib/letterhead-files";
import { BASIS, totals, type QuoteInput, type QuoteLine } from "@/lib/quote";

export const runtime = "nodejs";

/** The quotation exactly as it is on screen — before (or without) saving — as a PDF on the letterhead. */
export async function POST(req: Request) {
  if (!(await getStaff())) return NextResponse.json({ error: "Please sign in." }, { status: 401 });
  let q: QuoteInput & { number?: string | null; status?: string; download?: boolean };
  try { q = await req.json(); } catch { return NextResponse.json({ error: "Bad request." }, { status: 400 }); }
  const str = (v: unknown, max = 3000) => String(v ?? "").slice(0, max);
  const lines: QuoteLine[] = (Array.isArray(q.lines) ? q.lines : []).slice(0, 80).filter((l) => l && str(l.particulars).trim())
    .map((l) => ({ particulars: str(l.particulars, 200), detail: str(l.detail, 400), basis: (l.basis in BASIS ? l.basis : "one_time"),
      qty: Math.max(0, Number(l.qty) || 0), rate: Math.max(0, Number(l.rate) || 0), months: Math.max(1, Number(l.months) || 1), product_code: l.product_code ?? null }));
  const scope = (Array.isArray(q.scope) ? q.scope : []).slice(0, 60).map((s) => ({ module: str(s.module, 200), capability: str(s.capability, 600) })).filter((s) => s.module || s.capability);
  const discount_pct = Math.min(100, Math.max(0, Number(q.discount_pct) || 0)), gst_rate = Math.min(40, Math.max(0, Number(q.gst_rate) || 0));
  const supabase = await createClient();
  const [{ data: s }, { data: products }] = await Promise.all([
    supabase.from("billing_settings").select("trade_name,legal_name,gstin,signatory_name,signatory_title,seal_path,signature_path,show_seal").eq("id", true).maybeSingle(),
    supabase.from("products").select("code,seat_label"),
  ]);
  const seats = Object.fromEntries((products ?? []).map((x) => [x.code, x.seat_label]));
  const [lh, art] = await Promise.all([letterheadBytes(), signArt(s)]);
  const bytes = await quotePdf({
    number: q.number ?? null, status: q.status || "draft", quote_date: /^\d{4}-\d{2}-\d{2}$/.test(q.quote_date) ? q.quote_date : new Date().toISOString().slice(0, 10),
    valid_until: q.valid_until && /^\d{4}-\d{2}-\d{2}$/.test(q.valid_until) ? q.valid_until : null, currency: "INR",
    to_name: str(q.to_name, 200) || "—", to_attn: str(q.to_attn, 200), to_address: str(q.to_address, 500), to_gstin: str(q.to_gstin, 15), to_email: str(q.to_email, 200), to_phone: str(q.to_phone, 40),
    subject: str(q.subject, 300) || "Quotation", intro: str(q.intro), scope, lines, includes: str(q.includes), terms: str(q.terms, 6000),
    discount_pct, gst_rate, ...totals({ lines, discount_pct, gst_rate }), seller: s ?? {}, seat_label: (c) => (c && seats[c]) || "users",
  }, lh, art);
  const name = `Quotation_${String(q.number || "draft").replace(/[^\w-]+/g, "-")}_${str(q.to_name, 40).replace(/[^\w-]+/g, "-")}.pdf`;
  return new NextResponse(Buffer.from(bytes), { headers: { "content-type": "application/pdf", "cache-control": "private, no-store",
    "content-disposition": `${q.download ? "attachment" : "inline"}; filename="${name}"` } });
}
