import { NextResponse } from "next/server";
import { saveBackup } from "@/lib/backups";
import { runDailyBackup } from "@/lib/dailybackup";
import { alertEmail, sendMail } from "@/lib/mail";
// Nightly backup (vercel.json, from 12:10 AM India time, several passes ?pass=1..5). Each pass saves what is still open;
// the failure mail goes out only after the last pass (pass=5) if something is still not saved.
// Vercel sends "Authorization: Bearer <CRON_SECRET>"; without CRON_SECRET the route refuses to run.
export const dynamic = "force-dynamic";
export const maxDuration = 300;
export async function GET(req: Request) {
  const secret = process.env.CRON_SECRET;
  if (!secret) return NextResponse.json({ error: "CRON_SECRET is not set" }, { status: 503 });
  if (req.headers.get("authorization") !== `Bearer ${secret}`) return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  const pass = Number(new URL(req.url).searchParams.get("pass") || 1), last = pass >= 5, problems: string[] = [];
  let bytes = 0, res: Awaited<ReturnType<typeof runDailyBackup>> | null = null;
  if (pass === 1) { try { bytes = await saveBackup(); } catch (e) { problems.push(`Console data: ${(e as Error).message}`); } }
  try { res = await runDailyBackup(230_000); problems.push(...res.open.map((o) => `Not finished: ${o}`)); }
  catch (e) { problems.push((e as Error).message); }
  if (problems.length && last) {
    await sendMail({ kind: "backup_failed", to: await alertEmail(), subject: "KMR nightly backup failed", heading: "The nightly backup did not finish",
      paragraphs: ["Tonight's backup could not be completed after all passes. Open Console › Backups and take one by hand, then check System health.", ...problems.slice(0, 6).map((p) => `Problem: ${p}`)] });
  }
  return NextResponse.json({ ok: !problems.length, pass, bytes, ...res, problems }, { status: problems.length && last ? 500 : 200 });
}
