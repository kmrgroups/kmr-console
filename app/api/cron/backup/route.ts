import { NextResponse } from "next/server";
import { saveBackup } from "@/lib/backups";
// Nightly Console backup (vercel.json, 12:10 AM India time). Protected by CRON_SECRET when it is set.
export async function GET(req: Request) {
  const secret = process.env.CRON_SECRET;
  if (secret && req.headers.get("authorization") !== `Bearer ${secret}`) return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  try { return NextResponse.json({ ok: true, bytes: await saveBackup() }); }
  catch (e) { return NextResponse.json({ error: (e as Error).message }, { status: 500 }); }
}
