import { NextResponse } from "next/server";
import { createClient } from "@supabase/supabase-js";
import { sendMail, type Brand } from "@/lib/mail";
import { buildFinance, type FinTargets } from "@/lib/finmail";
import { env } from "@/lib/env";

// Administration › Finance mail › "Send test mail": a company administrator gets today's finance mail (or sends it to one typed address). Nothing is marked as sent.
// The signed-in user's own access token is used, so only that company's administrators pass.
export const dynamic = "force-dynamic";
export const maxDuration = 30;

export async function POST(req: Request) {
  const token = (req.headers.get("authorization") || "").replace(/^Bearer\s+/i, "");
  if (!token) return NextResponse.json({ ok: false, error: "Please sign in again." }, { status: 401 });
  let body: { slug?: string; to?: string } = {};
  try { body = await req.json(); } catch { /* empty body */ }
  const slug = String(body.slug || "").trim();
  if (!slug) return NextResponse.json({ ok: false, error: "Company is missing." }, { status: 400 });
  try {
    const db = createClient(env.supabaseUrl, env.supabaseAnonKey, { auth: { persistSession: false }, global: { headers: { Authorization: `Bearer ${token}` } } });
    const { data, error } = await db.rpc("kmr_fin_test", { p_slug: slug });
    if (error) return NextResponse.json({ ok: false, error: error.message }, { status: /administrator/i.test(error.message) ? 403 : 400 });
    const s = data as { customer_id: string; slug: string; company: string; brand?: Brand; sections: Record<string, boolean>; targets: FinTargets; kpis: Record<string, unknown>; me: string };
    const to = String(body.to || s.me || "").trim().toLowerCase();
    if (!/^[^@\s]+@[^@\s]+\.[^@\s]{2,}$/.test(to)) return NextResponse.json({ ok: false, error: "Type a valid e-mail address." }, { status: 400 });
    const d = buildFinance({ slug: s.slug, company: s.company, brand: s.brand, sections: s.sections, targets: s.targets, kpis: s.kpis as never, platformUrl: env.platformUrl, test: true });
    if (d.sections === 0) return NextResponse.json({ ok: false, error: "No money figures are loaded yet (sales invoices, outstanding bills, expenses). Nothing was sent." }, { status: 400 });
    const r = await sendMail({ to, kind: "finance-digest-test", ref: s.slug, brand: s.brand, customerId: s.customer_id, subject: d.subject, heading: "Finance report (test)", paragraphs: ["This is a TEST mail. It shows what the morning mail would contain today. Nothing was marked as sent."], html: d.html, refNo: d.refNo, revision: d.revision });
    if (r === "sent") return NextResponse.json({ ok: true, to, sections: d.sections, act: d.counts.act, watch: d.counts.watch });
    if (r === "skipped") return NextResponse.json({ ok: false, error: "Mail is not set up on the server yet (RESEND_API_KEY / EMAIL_FROM). Nothing was sent." }, { status: 503 });
    return NextResponse.json({ ok: false, error: "The mail could not be sent. Please try again." }, { status: 502 });
  } catch (e) { return NextResponse.json({ ok: false, error: (e as Error).message }, { status: 500 }); }
}
