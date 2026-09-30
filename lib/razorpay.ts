import "server-only";
import { createHmac, timingSafeEqual } from "node:crypto";

/**
 * Razorpay (https://razorpay.com/docs/api/) without the SDK: orders through the REST API, signatures checked
 * with HMAC-SHA256. Test keys (rzp_test_…) take test cards / UPI and move no money; live keys (rzp_live_…) do.
 *   RAZORPAY_KEY_ID, RAZORPAY_KEY_SECRET — Dashboard › Account & Settings › API keys
 *   RAZORPAY_WEBHOOK_SECRET (optional)   — Dashboard › Webhooks, events payment.captured and order.paid
 */
export const razorpay = {
  get keyId() { return process.env.RAZORPAY_KEY_ID || ""; },
  get configured() { return Boolean(process.env.RAZORPAY_KEY_ID && process.env.RAZORPAY_KEY_SECRET); },
  get mode(): "test" | "live" { return (process.env.RAZORPAY_KEY_ID || "").startsWith("rzp_live_") ? "live" : "test"; },
};

/** Amount in the currency's smallest unit (paise, cents). */
export const toMinor = (amount: number | string) => Math.round(Number(amount) * 100);

export async function createOrder(amount: number | string, currency: string, receipt: string, notes: Record<string, string>) {
  const auth = Buffer.from(`${process.env.RAZORPAY_KEY_ID}:${process.env.RAZORPAY_KEY_SECRET}`).toString("base64");
  const res = await fetch("https://api.razorpay.com/v1/orders", {
    method: "POST",
    headers: { Authorization: `Basic ${auth}`, "Content-Type": "application/json" },
    body: JSON.stringify({ amount: toMinor(amount), currency, receipt: receipt.slice(0, 40), notes }),
    cache: "no-store",
  });
  const body = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(body?.error?.description || `Razorpay refused the order (${res.status}).`);
  return body as { id: string; amount: number; currency: string };
}

function safeEqualHex(a: string, b: string) {
  const x = Buffer.from(a, "utf8"), y = Buffer.from(b, "utf8");
  return x.length === y.length && timingSafeEqual(x, y);
}

/** Checkout's success handler: signature = HMAC(order_id|payment_id, key secret). */
export function checkoutSignatureOk(orderId: string, paymentId: string, signature: string, secret = process.env.RAZORPAY_KEY_SECRET || "") {
  if (!secret || !orderId || !paymentId || !signature) return false;
  return safeEqualHex(createHmac("sha256", secret).update(`${orderId}|${paymentId}`).digest("hex"), signature);
}

/** Webhook: X-Razorpay-Signature = HMAC(raw body, webhook secret). */
export function webhookSignatureOk(rawBody: string, signature: string, secret = process.env.RAZORPAY_WEBHOOK_SECRET || "") {
  if (!secret || !signature) return false;
  return safeEqualHex(createHmac("sha256", secret).update(rawBody).digest("hex"), signature);
}
