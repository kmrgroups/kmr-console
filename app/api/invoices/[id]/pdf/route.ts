import { NextResponse } from "next/server";
import { getStaff } from "@/lib/auth";
import { loadInvoice } from "@/lib/invoice-load";
import { invoicePdf } from "@/lib/invoice-pdf";
import { letterheadBytes, signArt } from "@/lib/letterhead-files";

export const runtime = "nodejs";

/** The invoice as a PDF on the letterhead — drafts included (watermarked DRAFT). */
export async function GET(req: Request, { params }: { params: Promise<{ id: string }> }) {
  if (!(await getStaff())) return NextResponse.json({ error: "Please sign in." }, { status: 401 });
  const { id } = await params;
  const d = await loadInvoice({ id });
  if (!d) return NextResponse.json({ error: "Invoice not found." }, { status: 404 });
  const [lh, art] = await Promise.all([letterheadBytes(), signArt(d.seller)]);
  const bytes = await invoicePdf(d.inv, d.lines, d.seller, d.buyer, lh, art);
  const name = `${d.inv.number ? "Invoice_" + d.inv.number.replace(/[^\w-]+/g, "-") : "Draft_invoice"}_${String(d.buyer.name ?? "").replace(/[^\w-]+/g, "-").slice(0, 40)}.pdf`;
  return new NextResponse(Buffer.from(bytes), { headers: { "content-type": "application/pdf", "cache-control": "private, no-store",
    "content-disposition": `${new URL(req.url).searchParams.get("download") === "1" ? "attachment" : "inline"}; filename="${name}"` } });
}
