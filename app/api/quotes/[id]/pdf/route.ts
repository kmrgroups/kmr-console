import { NextResponse } from "next/server";
import { getStaff } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { createAdminClient } from "@/lib/supabase/admin";
import { quotePdf } from "@/lib/quote-pdf";
import { signArt } from "@/lib/letterhead-files";

export const runtime = "nodejs";

/** The quotation as a PDF on the KMR letterhead (Seller details › Letterhead, or the built-in one). */
export async function GET(req: Request, { params }: { params: Promise<{ id: string }> }) {
  const staff = await getStaff();
  if (!staff) return NextResponse.json({ error: "Please sign in." }, { status: 401 });
  const { id } = await params;
  const supabase = await createClient();
  const [{ data: q }, { data: s }, { data: products }] = await Promise.all([
    supabase.from("quotes").select("*").eq("id", id).maybeSingle(),
    supabase.from("billing_settings").select("trade_name,legal_name,gstin,letterhead_path,signatory_name,signatory_title,seal_path,signature_path,show_seal").eq("id", true).maybeSingle(),
    supabase.from("products").select("code,seat_label"),
  ]);
  if (!q) return NextResponse.json({ error: "Quotation not found." }, { status: 404 });
  let letterhead: Uint8Array | null = null;
  if (s?.letterhead_path) {
    const { data } = await createAdminClient().storage.from("kmr-billing").download(s.letterhead_path);
    if (data) letterhead = new Uint8Array(await data.arrayBuffer());
  }
  const seats = Object.fromEntries((products ?? []).map((x) => [x.code, x.seat_label]));
  const art = await signArt(s);
  const bytes = await quotePdf({ ...q, seller: s ?? {}, seat_label: (c) => (c && seats[c]) || "users" }, letterhead, art);
  const name = `Quotation_${String(q.number ?? "draft").replace(/[^\w-]+/g, "-")}_${String(q.to_name).replace(/[^\w-]+/g, "-").slice(0, 40)}.pdf`;
  const download = new URL(req.url).searchParams.get("download") === "1";
  return new NextResponse(Buffer.from(bytes), { headers: {
    "content-type": "application/pdf", "cache-control": "private, no-store",
    "content-disposition": `${download ? "attachment" : "inline"}; filename="${name}"`,
  } });
}
