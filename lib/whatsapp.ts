import "server-only";
import { PDFDocument } from "pdf-lib";

/** WhatsApp Business Cloud API (Meta). Needs WA_TOKEN (permanent access token), WA_PHONE_ID and an approved template with an IMAGE header and 3 body variables
 *  ({{1}} unit, {{2}} date, {{3}} one-line summary) named WA_TEMPLATE (default kmr_daily_report). Without the keys nothing is sent ("skipped"). */
const G = "https://graph.facebook.com/v21.0";
/** Credentials come from the Vercel env first, else from the locked table console.wa_creds (server only, service role) — see waLoad(). */
const C: { token?: string; phone?: string; template?: string } = {};
export async function waLoad(db: { schema: (s: string) => { rpc: (f: string) => PromiseLike<{ data: unknown }> } }) {
  C.token = process.env.WA_TOKEN; C.phone = process.env.WA_PHONE_ID; C.template = process.env.WA_TEMPLATE;
  if (!C.token || !C.phone) {
    const { data } = await db.schema("public").rpc("kmr_wa_creds");
    const d = (data ?? {}) as { token?: string; phone_id?: string; template?: string };
    C.token = C.token || d.token; C.phone = C.phone || d.phone_id; C.template = C.template || d.template;
  }
}
export const waReady = () => !!(C.token && C.phone);

export async function waUpload(png: Uint8Array): Promise<string> {
  const fd = new FormData();
  fd.append("messaging_product", "whatsapp"); fd.append("type", "image/png");
  fd.append("file", new Blob([png as unknown as BlobPart], { type: "image/png" }), "report.png");
  const r = await fetch(`${G}/${C.phone}/media`, { method: "POST", headers: { Authorization: `Bearer ${C.token}` }, body: fd });
  const j = (await r.json()) as { id?: string; error?: { message?: string } };
  if (!r.ok || !j.id) throw new Error(j.error?.message || `media upload failed (${r.status})`);
  return j.id;
}

export async function waSend(to: string, mediaId: string, vars: [string, string, string]): Promise<"sent" | "failed"> {
  const r = await fetch(`${G}/${C.phone}/messages`, {
    method: "POST", headers: { Authorization: `Bearer ${C.token}`, "Content-Type": "application/json" },
    body: JSON.stringify({ messaging_product: "whatsapp", to, type: "template", template: { name: C.template || "kmr_daily_report", language: { code: "en" }, components: [
      { type: "header", parameters: [{ type: "image", image: { id: mediaId } }] },
      { type: "body", parameters: vars.map((text) => ({ type: "text", text: text.replace(/[\r\n\t]+/g, " ").slice(0, 900) })) }] } }) });
  if (!r.ok) throw new Error(((await r.json()) as { error?: { message?: string } }).error?.message || `send failed (${r.status})`);
  return "sent";
}

/** One PDF per unit (a page per sheet): the report then goes as ONE message per person per unit. */
export async function waPdf(pics: Uint8Array[]): Promise<Uint8Array> {
  const doc = await PDFDocument.create();
  for (const png of pics) { const im = await doc.embedPng(png); const pg = doc.addPage([im.width, im.height]); pg.drawImage(im, { x: 0, y: 0, width: im.width, height: im.height }); }
  return doc.save();
}

export async function waUploadPdf(pdf: Uint8Array): Promise<string> {
  const fd = new FormData();
  fd.append("messaging_product", "whatsapp"); fd.append("type", "application/pdf");
  fd.append("file", new Blob([pdf as unknown as BlobPart], { type: "application/pdf" }), "report.pdf");
  const r = await fetch(`${G}/${C.phone}/media`, { method: "POST", headers: { Authorization: `Bearer ${C.token}` }, body: fd });
  const j = (await r.json()) as { id?: string; error?: { message?: string } };
  if (!r.ok || !j.id) throw new Error(j.error?.message || `media upload failed (${r.status})`);
  return j.id;
}

/** Template with a DOCUMENT header and the same 3 body variables, named WA_TEMPLATE_DOC (default kmr_daily_report_pdf). */
export async function waSendDoc(to: string, mediaId: string, filename: string, vars: [string, string, string]): Promise<"sent" | "failed"> {
  const r = await fetch(`${G}/${C.phone}/messages`, {
    method: "POST", headers: { Authorization: `Bearer ${C.token}`, "Content-Type": "application/json" },
    body: JSON.stringify({ messaging_product: "whatsapp", to, type: "template", template: { name: process.env.WA_TEMPLATE_DOC || "kmr_daily_report_pdf", language: { code: "en" }, components: [
      { type: "header", parameters: [{ type: "document", document: { id: mediaId, filename } }] },
      { type: "body", parameters: vars.map((text) => ({ type: "text", text: text.replace(/[\r\n\t]+/g, " ").slice(0, 900) })) }] } }) });
  if (!r.ok) throw new Error(((await r.json()) as { error?: { message?: string } }).error?.message || `send failed (${r.status})`);
  return "sent";
}
