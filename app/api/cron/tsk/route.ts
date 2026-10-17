import { NextResponse } from "next/server";
import { createAdminClient } from "@/lib/supabase/admin";
import { deliverPending } from "@/lib/tsk-push";

// ActionTrack: every morning (vercel.json) raises "due tomorrow / due today / overdue" reminders and sends all waiting alerts. Needs CRON_SECRET, like the backup route.
export const dynamic = "force-dynamic";
export const maxDuration = 60;
export async function GET(req: Request) {
  const secret = process.env.CRON_SECRET;
  if (!secret) return NextResponse.json({ error: "CRON_SECRET is not set" }, { status: 503 });
  if (req.headers.get("authorization") !== `Bearer ${secret}`) return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  try {
    const { data, error } = await createAdminClient().schema("public").rpc("kmr_tsk_due_scan");
    if (error) throw new Error(error.message);
    return NextResponse.json({ ok: true, reminders: data, ...(await deliverPending(500)) });
  } catch (e) { return NextResponse.json({ error: (e as Error).message }, { status: 500 }); }
}
