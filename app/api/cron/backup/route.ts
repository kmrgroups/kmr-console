import { NextResponse } from "next/server";
import { saveBackup } from "@/lib/backups";
import { alertEmail, sendMail } from "@/lib/mail";
// Nightly backup (vercel.json, 12:10 AM India time). Vercel sends "Authorization: Bearer <CRON_SECRET>";
// without CRON_SECRET set, the route refuses to run (so nobody else can trigger it).
export const dynamic = "force-dynamic";
export const maxDuration = 60;
export async function GET(req: Request) {
  const secret = process.env.CRON_SECRET;
  if (!secret) return NextResponse.json({ error: "CRON_SECRET is not set" }, { status: 503 });
  if (req.headers.get("authorization") !== `Bearer ${secret}`) return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  try { return NextResponse.json({ ok: true, bytes: await saveBackup() }); }
  catch (e) {
    await sendMail({ kind: "backup_failed", to: await alertEmail(), subject: "KMR nightly backup failed", heading: "The nightly backup failed",
      paragraphs: ["Tonight's backup could not be saved. Open Console › Backups and take one by hand, then check System health.", `Error: ${(e as Error).message}`] });
    return NextResponse.json({ error: (e as Error).message }, { status: 500 });
  }
}
