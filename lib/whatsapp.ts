import "server-only";

/** WhatsApp Business Cloud API (Meta). Needs WA_TOKEN (permanent access token), WA_PHONE_ID and an approved template with an IMAGE header and 3 body variables
 *  ({{1}} unit, {{2}} date, {{3}} one-line summary) named WA_TEMPLATE (default kmr_daily_report). Without the keys nothing is sent ("skipped"). */
const G = "https://graph.facebook.com/v21.0";
export const waReady = () => !!(process.env.WA_TOKEN && process.env.WA_PHONE_ID);

export async function waUpload(png: Uint8Array): Promise<string> {
  const fd = new FormData();
  fd.append("messaging_product", "whatsapp"); fd.append("type", "image/png");
  fd.append("file", new Blob([png as unknown as BlobPart], { type: "image/png" }), "report.png");
  const r = await fetch(`${G}/${process.env.WA_PHONE_ID}/media`, { method: "POST", headers: { Authorization: `Bearer ${process.env.WA_TOKEN}` }, body: fd });
  const j = (await r.json()) as { id?: string; error?: { message?: string } };
  if (!r.ok || !j.id) throw new Error(j.error?.message || `media upload failed (${r.status})`);
  return j.id;
}

export async function waSend(to: string, mediaId: string, vars: [string, string, string]): Promise<"sent" | "failed"> {
  const r = await fetch(`${G}/${process.env.WA_PHONE_ID}/messages`, {
    method: "POST", headers: { Authorization: `Bearer ${process.env.WA_TOKEN}`, "Content-Type": "application/json" },
    body: JSON.stringify({ messaging_product: "whatsapp", to, type: "template", template: { name: process.env.WA_TEMPLATE || "kmr_daily_report", language: { code: "en" }, components: [
      { type: "header", parameters: [{ type: "image", image: { id: mediaId } }] },
      { type: "body", parameters: vars.map((text) => ({ type: "text", text: text.replace(/[\r\n\t]+/g, " ").slice(0, 900) })) }] } }) });
  if (!r.ok) throw new Error(((await r.json()) as { error?: { message?: string } }).error?.message || `send failed (${r.status})`);
  return "sent";
}
