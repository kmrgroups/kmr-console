import { NextResponse } from "next/server";
import { resetDemoWorkspace } from "@/lib/test-data";
// Nightly reset of the KMR demo workspace (vercel.json, 12:40 AM India time, just after the backup): its sample data is
// cleared and reloaded so every prospect finds it as new. Needs CRON_SECRET, like the backup route.
export const dynamic = "force-dynamic";
export const maxDuration = 60;
export async function GET(req: Request) {
  const secret = process.env.CRON_SECRET;
  if (!secret) return NextResponse.json({ error: "CRON_SECRET is not set" }, { status: 503 });
  if (req.headers.get("authorization") !== `Bearer ${secret}`) return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  try { return NextResponse.json({ ok: true, demo: await resetDemoWorkspace() }); }
  catch (e) { return NextResponse.json({ error: (e as Error).message }, { status: 500 }); }
}
