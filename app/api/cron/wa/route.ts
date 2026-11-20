import { NextResponse } from "next/server";
import { cronDenied } from "@/lib/cronauth";
import { createAdminClient } from "@/lib/supabase/admin";
import { renderAll, type WaKpis } from "@/lib/wareport";
import { waReady, waUpload, waSend } from "@/lib/whatsapp";

// Evening WhatsApp report (vercel.json, 19:30 India time): for every unit with the report switched on, one picture (sales value plan / done / pending, today's invoices, dispatch status)
// goes to the unit in-charges and the extra people. Settings: customer page › plant › WhatsApp report (console.wa_settings, migration 0183).
export const dynamic = "force-dynamic";
export const maxDuration = 300;
const inr = (n: number) => "Rs " + Math.round(n).toLocaleString("en-IN");

export async function GET(req: Request) {
  const denied = await cronDenied(req);
  if (denied) return NextResponse.json({ error: denied.error }, { status: denied.status });
  try {
    const db = createAdminClient();
    const { data, error } = await db.schema("public").rpc("kmr_wa_scan");
    if (error) throw new Error(error.message);
    const units = (data ?? []) as { customer_id: string; unit: string; recipients: { name: string; phone: string }[]; kpis: WaKpis }[];
    let sent = 0, failed = 0, skipped = 0;
    for (const u of units) {
      const log = (to: { name: string; phone: string }, status: string, err?: string) => db.schema("console").from("wa_log").insert({ customer_id: u.customer_id, to_name: to.name, to_phone: to.phone, status, error: err?.slice(0, 500) ?? null });
      if (!waReady()) { skipped += u.recipients.length; for (const r of u.recipients) await log(r, "skipped", "WhatsApp account not connected (WA_TOKEN / WA_PHONE_ID)"); continue; }
      try {
        const k = u.kpis, pics = await renderAll(u.unit, k), media: { title: string; id: string }[] = [];
        for (const p of pics) media.push({ title: p.title, id: await waUpload(p.png) });
        const day = k.day.split("-").reverse().join("-");
        const first = `Invoices today ${k.invoices.length} (${inr(k.invoices.reduce((a, i) => a + Number(i.total || 0), 0))}); month plan ${inr(k.plan_val)}, done ${inr(k.actual_val)}, pending ${inr(Math.max(0, k.plan_val - k.actual_val))}`;
        let ok = 0;
        for (const r of u.recipients) {
          try { for (let i = 0; i < media.length; i++) await waSend(r.phone, media[i].id, [u.unit, day, i === 0 ? first : media[i].title]); ok++; sent++; await log(r, "sent"); }
          catch (e) { failed++; await log(r, "failed", (e as Error).message); }
        }
        if (ok > 0) await db.schema("public").rpc("kmr_wa_mark", { p_cid: u.customer_id });
      } catch (e) { failed += u.recipients.length; await log({ name: "all", phone: "" }, "failed", (e as Error).message); }
    }
    return NextResponse.json({ ok: true, units: units.length, sent, skipped, failed });
  } catch (e) { return NextResponse.json({ error: (e as Error).message }, { status: 500 }); }
}
