import { NextResponse } from "next/server";
import { createClient } from "@supabase/supabase-js";
import { sendMail, type Brand } from "@/lib/mail";
import { env } from "@/lib/env";

// Calibration Hub › Mail alert › "Send test mail": an administrator gets (or sends to one typed address) the list of gauges that are inside the alert window today.
// Nothing is marked as mailed, so the real morning mail is not affected. The signed-in user's own access token is used, so only a Calibration Hub administrator passes.
export const dynamic = "force-dynamic";
export const maxDuration = 30;
type Row = { tag: string; name: string; gauge_class: string | null; department: string | null; location: string | null; supplier: string | null; next_due: string; days_left: number };
const dmy = (d: string) => d.split("-").reverse().join("-");
const MAX_ROWS = 60;

export async function POST(req: Request) {
  const token = (req.headers.get("authorization") || "").replace(/^Bearer\s+/i, "");
  if (!token) return NextResponse.json({ ok: false, error: "Please sign in again." }, { status: 401 });
  let body: { slug?: string; to?: string } = {};
  try { body = await req.json(); } catch { /* empty body */ }
  const slug = String(body.slug || "").trim();
  if (!slug) return NextResponse.json({ ok: false, error: "Company is missing." }, { status: 400 });
  try {
    const db = createClient(env.supabaseUrl, env.supabaseAnonKey, { auth: { persistSession: false }, global: { headers: { Authorization: `Bearer ${token}` } } });
    const { data, error } = await db.rpc("kmr_cal_test_list", { p_slug: slug });
    if (error) return NextResponse.json({ ok: false, error: error.message }, { status: /administrator/i.test(error.message) ? 403 : 400 });
    const s = data as { slug: string; company: string; brand?: Brand; days_before: number; me: string; rows: Row[] };
    const to = String(body.to || s.me || "").trim().toLowerCase();
    if (!/^[^@\s]+@[^@\s]+\.[^@\s]{2,}$/.test(to)) return NextResponse.json({ ok: false, error: "Type a valid e-mail address." }, { status: 400 });
    const n = s.rows.length, shown = s.rows.slice(0, MAX_ROWS);
    const paragraphs = [
      "This is a TEST mail from Calibration Hub. It shows what the morning alert would send today. Nothing was marked as mailed.",
      n ? `${n} gauge${n === 1 ? "" : "s"} will become overdue for calibration within ${s.days_before} days.` : `No gauge is due within ${s.days_before} days today.`,
      ...(n > shown.length ? [`The first ${shown.length} are listed here; open Calibration Hub for the full list.`] : []),
    ];
    const rows: [string, string][] = shown.map((r) => [
      `${r.tag} · ${r.name}`,
      `Due ${dmy(r.next_due)} (${r.days_left} day${r.days_left === 1 ? "" : "s"}) · ${r.gauge_class ?? "Variable"}${r.location ? " · " + r.location : r.department ? " · " + r.department : ""}${r.supplier ? " · Supplier: " + r.supplier : ""}`,
    ]);
    const r = await sendMail({
      to, kind: "calibration-due-test", ref: s.slug, brand: s.brand, customerSlug: s.slug,
      subject: `TEST — Calibration due within ${s.days_before} days — ${n} gauge${n === 1 ? "" : "s"} · ${s.company}`,
      heading: "Gauges going to overdue (test)", paragraphs, rows,
      button: { label: "Open Calibration Hub", url: `${env.platformUrl}/it/calibration.html?kmr=1&co=${encodeURIComponent(s.slug)}#go=var` },
    });
    if (r === "sent") return NextResponse.json({ ok: true, to, count: n });
    if (r === "skipped") return NextResponse.json({ ok: false, error: "Mail is not set up on the server yet (RESEND_API_KEY / EMAIL_FROM). Nothing was sent." }, { status: 503 });
    return NextResponse.json({ ok: false, error: "The mail could not be sent. Please try again." }, { status: 502 });
  } catch (e) { return NextResponse.json({ ok: false, error: (e as Error).message }, { status: 500 }); }
}
