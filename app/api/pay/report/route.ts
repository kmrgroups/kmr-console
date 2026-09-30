import { NextResponse } from "next/server";
import { createAdminClient } from "@/lib/supabase/admin";
import { clientIp, rateOk } from "@/lib/rate";
import { mailPaymentReported } from "@/lib/notify";

export const dynamic = "force-dynamic";

/** The customer reports a bank / UPI payment on the pay link; KMR confirms it after checking the bank statement. */
export async function POST(req: Request) {
  if (!(await rateOk(`pay-report:${await clientIp()}`, 10, 3600))) return NextResponse.json({ error: "Too many attempts. Please try again in an hour, or email us." }, { status: 429 });
  const b = (await req.json().catch(() => ({}))) as Record<string, unknown>;
  const token = String(b.token ?? "");
  if (!/^[a-f0-9]{20,64}$/.test(token)) return NextResponse.json({ error: "Invalid link." }, { status: 400 });
  const amount = Number(String(b.amount ?? "").replace(/[, ]/g, ""));
  if (!Number.isFinite(amount) || amount <= 0) return NextResponse.json({ error: "Enter the amount you paid." }, { status: 400 });
  const paidOn = String(b.paid_on ?? "");
  if (!/^\d{4}-\d{2}-\d{2}$/.test(paidOn)) return NextResponse.json({ error: "Enter the date you paid." }, { status: 400 });
  const { error } = await createAdminClient().rpc("report_payment", {
    p_token: token, p_method: String(b.method ?? ""), p_reference: String(b.reference ?? "").slice(0, 80),
    p_paid_on: paidOn, p_amount: amount, p_payer: String(b.payer ?? "").slice(0, 120) || null,
  });
  if (error) return NextResponse.json({ error: error.message }, { status: 400 });
  await mailPaymentReported(token, amount, String(b.reference ?? "").slice(0, 80), String(b.payer ?? "").slice(0, 120) || null);
  return NextResponse.json({ ok: true });
}
