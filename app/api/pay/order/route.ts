import { NextResponse } from "next/server";
import { createAdminClient } from "@/lib/supabase/admin";
import { createOrder, razorpay, toMinor } from "@/lib/razorpay";

export const dynamic = "force-dynamic";

/** Starts a Razorpay payment for an issued invoice. The amount always comes from the database, never the browser. */
export async function POST(req: Request) {
  try {
    if (!razorpay.configured) return NextResponse.json({ error: "Online payment is not switched on yet. Please pay by bank transfer or UPI." }, { status: 503 });
    const { token } = await req.json().catch(() => ({}));
    if (typeof token !== "string" || !/^[a-f0-9]{20,64}$/.test(token)) return NextResponse.json({ error: "Invalid link." }, { status: 400 });
    const db = createAdminClient();
    const { data } = await db.rpc("invoice_for_token", { p_token: token });
    const inv = data?.invoice;
    if (!inv) return NextResponse.json({ error: "Invoice not found." }, { status: 404 });
    if (inv.status !== "issued") return NextResponse.json({ error: inv.status === "paid" ? "This invoice is already paid." : "This invoice cannot be paid." }, { status: 409 });
    const order = await createOrder(inv.total, inv.currency, inv.number, { invoice: inv.number, kmr_invoice_id: inv.id });
    const { error } = await db.rpc("razorpay_order_started", { p_token: token, p_order_id: order.id, p_mode: razorpay.mode, p_amount: inv.total, p_currency: inv.currency });
    if (error) return NextResponse.json({ error: error.message }, { status: 409 });
    return NextResponse.json({
      key: razorpay.keyId, order_id: order.id, amount: toMinor(inv.total), currency: inv.currency,
      name: inv.seller?.legal_name || "KMR Group of Companies", description: `Invoice ${inv.number}`,
      prefill: { name: inv.buyer?.contact_name || inv.buyer?.name || "", email: inv.buyer?.contact_email || "" },
      notes: { invoice: inv.number },
    });
  } catch (e) {
    return NextResponse.json({ error: (e as Error).message }, { status: 502 });
  }
}
