import "server-only";
import { createAdminClient } from "@/lib/supabase/admin";

/**
 * Email through Resend (the same provider as the HRM). Set RESEND_API_KEY and EMAIL_FROM
 * (e.g. "KMR Group of Companies <no-reply@kmr-groups.com>") in Vercel. Without them nothing is sent and every
 * attempt is recorded as "skipped" in the email log (Console › System health), so nothing fails.
 * ALERT_EMAIL receives KMR's own notices (payment reports, new orders, errors); it defaults to the seller email.
 */
export type Mail = { to: string; subject: string; heading: string; paragraphs: string[]; button?: { label: string; url: string }; rows?: [string, string][]; kind: string; ref?: string; replyTo?: string };

const esc = (s: string) => s.replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]!));

type Seller = { name: string; email: string; phone: string; address: string; gstin: string };
let sellerCache: { at: number; v: Seller } | null = null;
export async function seller(): Promise<Seller> {
  if (sellerCache && Date.now() - sellerCache.at < 5 * 60_000) return sellerCache.v;
  const { data } = await createAdminClient().from("billing_settings").select("trade_name,legal_name,email,phone,address,city,state,postal_code,gstin").maybeSingle();
  const v: Seller = {
    name: data?.trade_name || data?.legal_name || "KMR Group of Companies", email: data?.email || "info@kmr-groups.com", phone: data?.phone || "",
    address: [data?.address, data?.city, data?.state, data?.postal_code].filter(Boolean).join(", "), gstin: data?.gstin || "",
  };
  sellerCache = { at: Date.now(), v };
  return v;
}
export const alertEmail = async () => process.env.ALERT_EMAIL || (await seller()).email;

export async function renderMail(m: Mail): Promise<string> {
  const s = await seller();
  const rows = m.rows?.length ? `<table role="presentation" style="width:100%;border-collapse:collapse;margin:18px 0;font-size:14px">${m.rows.map(([k, v]) =>
    `<tr><td style="padding:8px 0;border-bottom:1px solid #eee;color:#5e6778;width:40%">${esc(k)}</td><td style="padding:8px 0;border-bottom:1px solid #eee;color:#0b1c3a;font-weight:600">${esc(v)}</td></tr>`).join("")}</table>` : "";
  const btn = m.button ? `<p style="margin:26px 0"><a href="${esc(m.button.url)}" style="background:#c6a15b;color:#0b1c3a;text-decoration:none;font-weight:700;padding:12px 22px;display:inline-block">${esc(m.button.label)}</a></p>` : "";
  return `<!doctype html><html><body style="margin:0;background:#f4f1ea;font-family:Segoe UI,Arial,sans-serif;color:#101828">
<table role="presentation" width="100%" style="background:#f4f1ea;padding:24px 12px"><tr><td align="center">
<table role="presentation" width="100%" style="max-width:600px;background:#ffffff;border:1px solid #e6dfd1">
<tr><td style="background:#0b1c3a;padding:18px 26px;color:#ffffff;font-size:18px;font-weight:700;font-family:Georgia,serif">${esc(s.name)}<div style="height:2px;background:#c6a15b;margin-top:12px;width:56px"></div></td></tr>
<tr><td style="padding:26px">
<h1 style="margin:0 0 14px;font-size:20px;color:#0b1c3a;font-family:Georgia,serif">${esc(m.heading)}</h1>
${m.paragraphs.map((p) => `<p style="margin:0 0 12px;font-size:15px;line-height:1.6">${esc(p)}</p>`).join("")}
${rows}${btn}
</td></tr>
<tr><td style="padding:16px 26px;border-top:1px solid #e6dfd1;font-size:12px;color:#5e6778;line-height:1.6">${esc(s.name)}${s.address ? ` · ${esc(s.address)}` : ""}<br>${esc(s.email)}${s.phone ? ` · ${esc(s.phone)}` : ""}${s.gstin ? ` · GSTIN ${esc(s.gstin)}` : ""}</td></tr>
</table></td></tr></table></body></html>`;
}

async function log(m: Mail, status: "sent" | "skipped" | "failed", error?: string) {
  await createAdminClient().from("email_log").insert({ app: "console", kind: m.kind, to_addr: m.to.slice(0, 200), subject: m.subject.slice(0, 200), status, error: error?.slice(0, 500) ?? null, ref: m.ref ?? null });
}

/** Sends one email; never throws (a failed email must not undo the business action). */
export async function sendMail(m: Mail): Promise<"sent" | "skipped" | "failed"> {
  try {
    if (!m.to || !/^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(m.to)) return "skipped";
    const key = process.env.RESEND_API_KEY, from = process.env.EMAIL_FROM;
    if (!key || !from) { await log(m, "skipped", "RESEND_API_KEY / EMAIL_FROM not set"); return "skipped"; }
    const r = await fetch(process.env.RESEND_API_URL || "https://api.resend.com/emails", {
      method: "POST", headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
      body: JSON.stringify({ from, to: [m.to], subject: m.subject, html: await renderMail(m), reply_to: m.replyTo || (await seller()).email }),
      signal: AbortSignal.timeout(8000),
    });
    if (!r.ok) { const t = await r.text().catch(() => ""); await log(m, "failed", `${r.status} ${t}`); return "failed"; }
    await log(m, "sent"); return "sent";
  } catch (e) {
    try { await log(m, "failed", (e as Error).message); } catch { /* logging must not throw */ }
    return "failed";
  }
}
