import { NextResponse } from "next/server";
import { createAdminClient } from "@/lib/supabase/admin";
import { sendMail, type Brand } from "@/lib/mail";
import { buildDigest, type Targets } from "@/lib/digest";
import { env } from "@/lib/env";

// Daily management mail (vercel.json, 08:30 India time): one mail per plant with the dashboards and KPIs of every app the plant uses, what is OK, where management
// has to concentrate and what each team has to do. Settings: Administration › Daily management mail (console.digest_settings, migration 0128).
// Needs CRON_SECRET and RESEND_API_KEY + EMAIL_FROM. Without the mail keys nothing is marked as sent, so the mail goes out once they are set.
export const dynamic = "force-dynamic";
export const maxDuration = 120;

type Scan = { customer_id: string; slug: string; company: string; brand?: Brand; recipients: string[]; sections: Record<string, boolean>; targets: Targets; kpis: Record<string, unknown> };

export async function GET(req: Request) {
  const secret = process.env.CRON_SECRET;
  if (!secret) return NextResponse.json({ error: "CRON_SECRET is not set" }, { status: 503 });
  if (req.headers.get("authorization") !== `Bearer ${secret}`) return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  try {
    const db = createAdminClient().schema("public");
    const { data, error } = await db.rpc("kmr_digest_scan");
    if (error) throw new Error(error.message);
    const scans = (data ?? []) as Scan[];
    let mails = 0, skipped = 0, failed = 0;
    const fail = async (slug: string, msg: string) => { failed++; await createAdminClient().from("email_log").insert({ app: "console", kind: "mgmt-digest", to_addr: slug.slice(0, 200), subject: "Daily management mail could not be built", status: "failed", error: msg.slice(0, 500), ref: slug }); };
    for (const s of scans) {
     try {
      const d = buildDigest({ slug: s.slug, company: s.company, brand: s.brand, sections: s.sections, targets: s.targets, kpis: s.kpis as never, platformUrl: env.platformUrl });
      if (d.sections === 0) { skipped += s.recipients.length; continue; }   // no app of this plant has data yet: nothing to report
      const res = await Promise.all(s.recipients.map((to) => sendMail({
        to, kind: "mgmt-digest", ref: s.slug, brand: s.brand, customerId: s.customer_id, subject: d.subject, heading: "Daily management report", paragraphs: [],
        html: d.html, refNo: d.refNo, revision: d.revision,
      })));
      const sent = res.filter((r) => r === "sent").length;
      mails += sent; skipped += res.filter((r) => r === "skipped").length; failed += res.filter((r) => r === "failed").length;
      if (sent > 0) await db.rpc("kmr_digest_mark", { p_cid: s.customer_id });
     } catch (e) { await fail(s.slug, (e as Error).message); }
    }
    return NextResponse.json({ ok: true, plants: scans.length, mails, skipped, failed });
  } catch (e) {
    await createAdminClient().from("email_log").insert({ app: "console", kind: "mgmt-digest", to_addr: "cron", subject: "Daily management mail job failed", status: "failed", error: (e as Error).message.slice(0, 500) });
    return NextResponse.json({ error: (e as Error).message }, { status: 500 });
  }
}
