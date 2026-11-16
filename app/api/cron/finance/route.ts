import { NextResponse } from "next/server";
import { createAdminClient } from "@/lib/supabase/admin";
import { sendMail, type Brand } from "@/lib/mail";
import { buildFinance, type FinTargets } from "@/lib/finmail";
import { env } from "@/lib/env";

// Finance mail for top management (vercel.json, 09:00 India time): sales value, receivables, payables, expenses against budget and sales, cash.
// Goes only to the addresses typed in Administration › Finance mail (console.fin_settings, migration 0129).
// Needs CRON_SECRET and RESEND_API_KEY + EMAIL_FROM. Without the mail keys nothing is marked as sent, so the mail goes out once they are set.
export const dynamic = "force-dynamic";
export const maxDuration = 120;

type Scan = { customer_id: string; slug: string; company: string; brand?: Brand; recipients: string[]; sections: Record<string, boolean>; targets: FinTargets; kpis: Record<string, unknown> };

export async function GET(req: Request) {
  const secret = process.env.CRON_SECRET;
  if (!secret) return NextResponse.json({ error: "CRON_SECRET is not set" }, { status: 503 });
  if (req.headers.get("authorization") !== `Bearer ${secret}`) return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  try {
    const db = createAdminClient().schema("public");
    const { data, error } = await db.rpc("kmr_fin_scan");
    if (error) throw new Error(error.message);
    const scans = (data ?? []) as Scan[];
    let mails = 0, skipped = 0, failed = 0;
    for (const s of scans) {
      const d = buildFinance({ slug: s.slug, company: s.company, brand: s.brand, sections: s.sections, targets: s.targets, kpis: s.kpis as never, platformUrl: env.platformUrl });
      if (d.sections === 0) { skipped += s.recipients.length; continue; }   // no money figures yet: nothing to report
      const res = await Promise.all(s.recipients.map((to) => sendMail({
        to, kind: "finance-digest", ref: s.slug, brand: s.brand, customerId: s.customer_id, subject: d.subject, heading: "Finance report", paragraphs: [],
        html: d.html, refNo: d.refNo, revision: d.revision,
      })));
      const sent = res.filter((r) => r === "sent").length;
      mails += sent; skipped += res.filter((r) => r === "skipped").length; failed += res.filter((r) => r === "failed").length;
      if (sent > 0) await db.rpc("kmr_fin_mark", { p_cid: s.customer_id });
    }
    return NextResponse.json({ ok: true, plants: scans.length, mails, skipped, failed });
  } catch (e) { return NextResponse.json({ error: (e as Error).message }, { status: 500 }); }
}
