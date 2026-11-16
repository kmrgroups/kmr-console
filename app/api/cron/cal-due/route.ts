import { NextResponse } from "next/server";

// The Calibration Hub due-date mail now travels inside the Daily management mail (see /api/cron/digest and Administration › Daily management mail).
// This address is kept only so an old schedule does not fail; it sends nothing, so no one receives the same gauge list twice.
export const dynamic = "force-dynamic";

export async function GET(req: Request) {
  const secret = process.env.CRON_SECRET;
  if (!secret) return NextResponse.json({ error: "CRON_SECRET is not set" }, { status: 503 });
  if (req.headers.get("authorization") !== `Bearer ${secret}`) return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  return NextResponse.json({ ok: true, skipped: "moved into the daily management mail" });
}
