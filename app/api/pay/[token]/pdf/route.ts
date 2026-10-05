import { NextResponse } from "next/server";
import { loadInvoice } from "@/lib/invoice-load";
import { invoicePdf } from "@/lib/invoice-pdf";
import { letterheadBytes, signArt } from "@/lib/letterhead-files";

export const runtime = "nodejs";

/** The customer's copy behind the pay link: issued, paid or cancelled invoices only (never drafts). */
export async function GET(req: Request, { params }: { params: Promise<{ token: string }> }) {
  const { token } = await params;
  if (!/^[a-f0-9]{20,64}$/.test(token)) return NextResponse.json({ error: "Not found." }, { status: 404 });
  const d = await loadInvoice({ token });
  if (!d || d.inv.status === "draft") return NextResponse.json({ error: "Not found." }, { status: 404 });
  const [lh, art] = await Promise.all([letterheadBytes(), signArt(d.seller)]);
  const bytes = await invoicePdf(d.inv, d.lines, d.seller, d.buyer, lh, art);
  const name = `Invoice_${String(d.inv.number ?? "").replace(/[^\w-]+/g, "-")}.pdf`;
  return new NextResponse(Buffer.from(bytes), { headers: { "content-type": "application/pdf", "cache-control": "private, no-store",
    "content-disposition": `${new URL(req.url).searchParams.get("download") === "1" ? "attachment" : "inline"}; filename="${name}"` } });
}
