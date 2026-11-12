import { NextResponse } from "next/server";
import { createAdminClient } from "@/lib/supabase/admin";
import { sendMail, type Brand } from "@/lib/mail";
import { env } from "@/lib/env";

// Calibration Hub: every morning (vercel.json) e-mails each company / plant that has the "mail alert" on the list of gauges that will
// become overdue within its chosen number of days (default 12). A gauge is mailed once per due date. Needs CRON_SECRET, like the backup route,
// and RESEND_API_KEY + EMAIL_FROM for the mail itself (same as the HRM). Without the mail keys nothing is marked as sent, so the list goes out once they are set.
export const dynamic = "force-dynamic";
export const maxDuration = 60;

type Row = { id: string; tag: string; name: string; gauge_class: string | null; department: string | null; location: string | null; supplier: string | null; next_due: string; days_left: number };
type Scan = { customer_id: string; slug: string; company: string; brand?: Brand; days_before: number; recipients: string[]; rows: Row[] };

const dmy = (d: string) => d.split("-").reverse().join("-");
const MAX_ROWS = 60;

export async function GET(req: Request) {
  const secret = process.env.CRON_SECRET;
  if (!secret) return NextResponse.json({ error: "CRON_SECRET is not set" }, { status: 503 });
  if (req.headers.get("authorization") !== `Bearer ${secret}`) return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  try {
    const db = createAdminClient().schema("public");
    const { data, error } = await db.rpc("kmr_cal_due_scan");
    if (error) throw new Error(error.message);
    const scans = (data ?? []) as Scan[];
    let mails = 0, skipped = 0, failed = 0, gauges = 0;
    for (const s of scans) {
      const n = s.rows.length;
      const shown = s.rows.slice(0, MAX_ROWS);
      const paragraphs = [
        `${n} gauge${n === 1 ? "" : "s"} will become overdue for calibration within ${s.days_before} days. Please plan the calibration now so none of them goes overdue.`,
        ...(n > shown.length ? [`The first ${shown.length} are listed here; open Calibration Hub for the full list.`] : []),
      ];
      const rows: [string, string][] = shown.map((r) => [
        `${r.tag} · ${r.name}`,
        `Due ${dmy(r.next_due)} (${r.days_left} day${r.days_left === 1 ? "" : "s"}) · ${r.gauge_class ?? "Variable"}${r.location ? " · " + r.location : r.department ? " · " + r.department : ""}${r.supplier ? " · Supplier: " + r.supplier : ""}`,
      ]);
      let sent = 0;
      for (const to of s.recipients) {
        const r = await sendMail({
          to, kind: "calibration-due", ref: s.slug, brand: s.brand,
          subject: `Calibration due within ${s.days_before} days — ${n} gauge${n === 1 ? "" : "s"} · ${s.company}`,
          heading: "Gauges going to overdue", paragraphs, rows,
          button: { label: "Open Calibration Hub", url: `${env.platformUrl}/it/calibration.html?kmr=1&co=${encodeURIComponent(s.slug)}#go=var` },
        });
        if (r === "sent") { sent++; mails++; } else if (r === "skipped") skipped++; else failed++;
      }
      // remember what was mailed only when at least one person really got it; otherwise the same list is tried again tomorrow
      if (sent > 0) { await db.rpc("kmr_cal_due_mark", { p_ids: s.rows.map((r) => r.id) }); gauges += n; }
    }
    return NextResponse.json({ ok: true, companies: scans.length, mails, skipped, failed, gauges });
  } catch (e) { return NextResponse.json({ error: (e as Error).message }, { status: 500 }); }
}
