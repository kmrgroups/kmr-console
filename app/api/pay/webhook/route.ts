import { NextResponse } from "next/server";
import { createAdminClient } from "@/lib/supabase/admin";
import { webhookSignatureOk } from "@/lib/razorpay";

export const dynamic = "force-dynamic";

/**
 * Razorpay webhook (optional but recommended): catches payments whose browser closed before confirming.
 * Dashboard › Webhooks › URL https://www.kmr-groups.com/it/console/api/pay/webhook, events payment.captured + order.paid,
 * secret = RAZORPAY_WEBHOOK_SECRET. Orders that are not Console invoices (e.g. website shop orders) are ignored.
 */
export async function POST(req: Request) {
  const raw = await req.text();
  if (!webhookSignatureOk(raw, req.headers.get("x-razorpay-signature") || "")) return NextResponse.json({ error: "bad signature" }, { status: 401 });
  let evt: { event?: string; payload?: { payment?: { entity?: { id?: string; order_id?: string; status?: string } } } };
  try { evt = JSON.parse(raw); } catch { return NextResponse.json({ error: "bad body" }, { status: 400 }); }
  const pay = evt.payload?.payment?.entity;
  if ((evt.event === "payment.captured" || evt.event === "order.paid") && pay?.order_id && pay.id) {
    await createAdminClient().rpc("razorpay_payment_verified", { p_order_id: pay.order_id, p_payment_id: pay.id, p_detail: { source: "webhook", event: evt.event } });
    // an unknown order (not a Console invoice) returns an error here — deliberately ignored
  }
  return NextResponse.json({ ok: true });
}
