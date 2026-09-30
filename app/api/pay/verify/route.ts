import { NextResponse } from "next/server";
import { createAdminClient } from "@/lib/supabase/admin";
import { checkoutSignatureOk } from "@/lib/razorpay";

export const dynamic = "force-dynamic";

/** Checkout's success handler posts here; only a correctly signed payment marks the invoice paid. */
export async function POST(req: Request) {
  const b = await req.json().catch(() => ({}));
  const { token, razorpay_order_id: orderId, razorpay_payment_id: paymentId, razorpay_signature: signature } = b as Record<string, string>;
  if (!checkoutSignatureOk(orderId, paymentId, signature)) return NextResponse.json({ error: "Payment could not be verified." }, { status: 400 });
  const db = createAdminClient();
  const { data: found } = await db.rpc("invoice_for_token", { p_token: String(token ?? "") });
  const { data, error } = await db.rpc("razorpay_payment_verified", { p_order_id: orderId, p_payment_id: paymentId, p_detail: { source: "checkout" } });
  if (error) return NextResponse.json({ error: error.message }, { status: 400 });
  if (!found || found.invoice.id !== data.invoice_id) return NextResponse.json({ error: "This payment belongs to another invoice." }, { status: 400 });
  return NextResponse.json({ ok: true, status: data.status });
}
