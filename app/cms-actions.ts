"use server";
import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { assertStaff } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { canEdit, sectionByKey, type Field, type Section } from "@/lib/cms";
import { MEDIA_BUCKET, PRIVATE_BUCKETS, web } from "@/lib/cms-server";
import { createAdminClient } from "@/lib/supabase/admin";
import { SAMPLE_TABLES, sampleRows } from "@/lib/cms-sample";
import { env } from "@/lib/env";
import type { ActionState } from "@/lib/action-state";
import { setFlash } from "@/lib/flash";
import { mailOrderUpdate } from "@/lib/notify";

const fail = (e: unknown): ActionState => ({ error: (e as Error).message });
const cap = (s: string) => s[0].toUpperCase() + s.slice(1);
const TOUCH = ["products", "hero_content", "company_info", "legal_pages", "job_openings", "job_applications", "site_settings"];

async function readField(f: Field, form: FormData): Promise<unknown> {
  const raw = form.get(f.k);
  const s = typeof raw === "string" ? raw.trim() : "";
  switch (f.type) {
    case "bool": return form.get(f.k) === "on";
    case "number": case "money": {
      if (!s) return null;
      const n = Number(s.replace(/[,₹\s]/g, ""));
      if (!Number.isFinite(n)) throw new Error(`${f.label}: enter a number.`);
      if (f.type === "money" && n < 0) throw new Error(`${f.label} cannot be negative.`);
      return n;
    }
    case "image": case "document": {
      // the browser already uploaded the file (startUpload); the field holds its address
      if (!s) return null;
      if (f.type === "image" && !/^https?:\/\//.test(s) && !s.startsWith("/")) throw new Error(`${f.label}: upload the file again.`);
      return s;
    }
    case "url": if (s && !/^(https?:\/\/|\/|#|mailto:|tel:)/i.test(s)) return `https://${s}`; return s || null;
    case "email": if (s && !/^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(s)) throw new Error(`${f.label}: enter a valid email.`); return s.toLowerCase() || null;
    default: return s || null;
  }
}

async function access(key: string) {
  const staff = await assertStaff();
  const s = sectionByKey(key);
  if (!s) throw new Error("Unknown section.");
  if (!canEdit(s, staff.role)) throw new Error("Your role can view this but not change it.");
  return s;
}
const refresh = (s: Section) => { revalidatePath(`/cms/${s.key}`); revalidatePath("/cms"); };

/** Create or update one record of a website section. */
export async function saveRecord(_: ActionState, form: FormData): Promise<ActionState> {
  const key = String(form.get("__section")); const id = String(form.get("__id") || "");
  let newId = id; let s!: Section;
  try {
    s = await access(key);
    const row: Record<string, unknown> = {};
    for (const f of s.fields) {
      if (f.readonly) continue;
      const v = await readField(f, form);
      if (f.required && (v === null || v === "")) return { error: `${f.label} is required.` };
      row[f.k] = v;
    }
    if (s.table === "legal_pages") {
      row.slug = String(row.slug ?? "").toLowerCase().replace(/[^a-z0-9-]+/g, "-").replace(/^-+|-+$/g, "");
      if (!row.slug) return { error: "Web address is required." };
    }
    Object.assign(row, s.scope ?? {});
    if (TOUCH.includes(s.table)) row.updated_at = new Date().toISOString();
    const db = web().from(s.table);
    if (id) {
      const { error } = await db.update(row).eq("id", id);
      if (error) return { error: /duplicate|unique/i.test(error.message) ? "That code / web address is already used by another record." : error.message };
    } else {
      if (s.noCreate) return { error: "New records cannot be added here." };
      for (const k of Object.keys(row)) if (row[k] === null) delete row[k];      // empty fields take the database default (e.g. posted today)
      const { data, error } = await db.insert(row).select("id").single();
      if (error) return { error: /duplicate|unique/i.test(error.message) ? "That code / web address is already used by another record." : error.message };
      newId = data.id;
    }
    refresh(s);
    await setFlash({ ok: id ? "Saved. The website shows the change within a minute." : `${cap(s.singular)} added.` });
  } catch (e) { return fail(e); }
  redirect(`/cms/${s.key}/${newId}`);
}

export async function deleteRecord(_: ActionState, form: FormData): Promise<ActionState> {
  const key = String(form.get("__section")); const id = String(form.get("__id") || ""); const back = form.get("__back") === "list";
  let s!: Section;
  try {
    s = await access(key);
    if (s.noDelete) return { error: "This cannot be deleted." };
    const { error } = await web().from(s.table).delete().eq("id", id);
    if (error) return { error: /foreign key|violates/i.test(error.message) ? `This ${s.singular} is used by orders or other records — hide it instead of deleting.` : error.message };
    refresh(s);
    if (back) return { ok: `${cap(s.singular)} deleted.` };
    await setFlash({ ok: `${cap(s.singular)} deleted.` });
  } catch (e) { return fail(e); }
  redirect(`/cms/${s.key}`);
}

const IMAGE_TYPES = /^(image\/(jpeg|png|webp|gif|svg\+xml|avif)|video\/(mp4|webm))$/;
const DOC_TYPES = /^(application\/pdf|image\/(jpeg|png|webp))$/;

/**
 * Upload step 1: a one-time signed link so the browser sends the file straight to storage (with a progress bar).
 * Large photos no longer pass through the Console server, whose request size is limited on Vercel.
 */
export async function startUpload(input: { section: string; field: string; name: string; type: string; size: number }):
  Promise<{ error?: string; signedUrl?: string; value?: string; preview?: string }> {
  try {
    const s = await access(input.section);
    const f = s.fields.find((x) => x.k === input.field && (x.type === "image" || x.type === "document") && !x.readonly);
    if (!f) return { error: "This field does not take files." };
    const image = f.type === "image";
    if (!(image ? IMAGE_TYPES : DOC_TYPES).test(input.type)) return { error: image ? "Choose a JPG, PNG, WebP or GIF photo (or an MP4 video)." : "Choose a PDF or an image." };
    const max = image ? (input.type.startsWith("video/") ? 50 : 25) : 10;
    if (input.size > max * 1024 * 1024) return { error: `The file is too large — up to ${max} MB.` };
    const ext = (input.name.split(".").pop() || "bin").toLowerCase().replace(/[^a-z0-9]/g, "").slice(0, 5) || "bin";
    const path = `${s.table}/${Date.now()}-${Math.random().toString(36).slice(2, 8)}.${ext}`;
    const bucket = image ? MEDIA_BUCKET : PRIVATE_BUCKETS[f.bucket ?? "records"];
    const store = createAdminClient().storage.from(bucket);
    const { data, error } = await store.createSignedUploadUrl(path);
    if (error || !data) return { error: `Could not start the upload: ${error?.message ?? "no link"}` };
    return image
      ? { signedUrl: data.signedUrl, value: store.getPublicUrl(path).data.publicUrl }
      : { signedUrl: data.signedUrl, value: "private:" + path };
  } catch (e) { return { error: (e as Error).message }; }
}

/** Show / hide on the website, straight from the list. */
export async function toggleVisible(_: ActionState, form: FormData): Promise<ActionState> {
  try {
    const s = await access(String(form.get("__section")));
    if (!s.visible) return { error: "This list has no show / hide." };
    const show = form.get("show") === "1";
    const { error } = await web().from(s.table).update({ [s.visible]: show }).eq("id", String(form.get("__id")));
    if (error) return { error: error.message };
    refresh(s);
    return { ok: show ? "Shown on the website." : "Hidden from the website." };
  } catch (e) { return fail(e); }
}

// ---------------- Shop orders: the staff member's own login calls the website's order functions (they check the role) ----------------
async function orderRpc(fn: string, args: Record<string, unknown>) {
  const staff = await assertStaff();
  if (!["owner", "admin", "sales"].includes(staff.role)) throw new Error("Only owners, administrators and sales staff can handle orders.");
  const supabase = await createClient();
  const { data, error } = await supabase.schema("public").rpc(fn, args);
  if (error) throw new Error(error.message);
  revalidatePath("/cms/orders");
  return data;
}
export async function confirmOrderPayment(_: ActionState, form: FormData): Promise<ActionState> {
  try {
    const r = await orderRpc("shop_confirm_payment", { p_order: form.get("id"), p_method: form.get("pay_method") || null, p_reference: form.get("reference") || null, p_paid_on: form.get("paid_on") || null });
    if (r === "paid") await mailOrderUpdate(String(form.get("id")), true);
    return { ok: r === "paid" ? "Payment confirmed — the order is paid and stock reduced." : `Payment confirmed (${r}).` };
  } catch (e) { return fail(e); }
}
export async function rejectOrderPayment(_: ActionState, form: FormData): Promise<ActionState> {
  try {
    await orderRpc("shop_reject_payment", { p_order: form.get("id"), p_reason: form.get("reason") });
    await mailOrderUpdate(String(form.get("id")), false, String(form.get("reason") ?? ""));
    return { ok: "Report rejected — the customer is emailed and sees the reason on their order page." };
  } catch (e) { return fail(e); }
}
export async function cancelShopOrder(_: ActionState, form: FormData): Promise<ActionState> {
  try { await orderRpc("shop_cancel_order", { p_order: form.get("id"), p_reason: form.get("reason") || "" }); return { ok: "Order cancelled." }; }
  catch (e) { return fail(e); }
}

/** Payment settings: online payment (Razorpay) and bank transfer / UPI on the order page. */
export async function savePaymentSettings(_: ActionState, form: FormData): Promise<ActionState> {
  try {
    const staff = await assertStaff();
    if (staff.role !== "owner" && staff.role !== "admin") return { error: "Only an owner or administrator can change payment settings." };
    const online = form.get("online_payment") === "on", bank = form.get("bank_transfer") === "on";
    if (!online && !bank) return { error: "Keep at least one way to pay switched on." };
    const { error } = await web().from("site_settings").update({ online_payment: online, bank_transfer: bank, updated_at: new Date().toISOString() }).eq("id", true);
    if (error) return { error: error.message };
    revalidatePath("/cms/payments");
    return { ok: "Saved. New and open orders use these settings." };
  } catch (e) { return fail(e); }
}

// ---------------- Sample content (Website CMS › Overview) ----------------
async function assertManagerStaff() {
  const staff = await assertStaff();
  if (staff.role !== "owner" && staff.role !== "admin") throw new Error("Only an owner or administrator can do this.");
}

export async function loadSampleContent(_: ActionState): Promise<ActionState> {
  try {
    await assertManagerStaff();
    const db = web(); const rows = sampleRows(env.platformUrl);
    const { count } = await db.from("hero_slides").select("id", { count: "exact", head: true }).eq("sample", true);
    if (count) return { error: "Sample content is already loaded. Remove it first to load it again." };
    let n = 0;
    for (const t of SAMPLE_TABLES) {
      for (const r of rows[t] as Record<string, unknown>[]) {          // one at a time: each row sets only its own fields
        const { error } = await db.from(t).insert({ ...r, sample: true, is_active: true });
        if (error) throw new Error(`${t}: ${/column .*sample/.test(error.message) ? "run the website's supabase/add-cms-update.sql first" : error.message}`);
        n++;
      }
    }
    // photos only where there is none yet
    const { data: c } = await db.from("company_info").select("id,about_image_url,founder_photo_url").limit(1).maybeSingle();
    if (c) {
      const patch: Record<string, string> = {};
      if (!c.about_image_url) patch.about_image_url = rows.company.about_image_url;
      if (!c.founder_photo_url) patch.founder_photo_url = rows.company.founder_photo_url;
      if (Object.keys(patch).length) await db.from("company_info").update(patch).eq("id", c.id);
    }
    const { data: vs } = await db.from("verticals").select("id,slug,image_url");
    for (const v of vs ?? []) if (!v.image_url && v.slug && rows.verticals[v.slug]) await db.from("verticals").update({ image_url: rows.verticals[v.slug] }).eq("id", v.id);
    revalidatePath("/cms", "layout");
    await setFlash({ ok: `Loaded ${n} sample items (slides, numbers, products, programmes, a solution, a trade item, job openings, people and gallery photos). They are marked “sample”. The website shows them within a minute.` });
  } catch (e) { return fail(e); }
  redirect("/cms");
}

export async function removeSampleContent(_: ActionState): Promise<ActionState> {
  try {
    await assertManagerStaff();
    const db = web(); const site = `${env.platformUrl}/sample/`;
    let removed = 0, hidden = 0;
    for (const t of SAMPLE_TABLES) {
      const { data, error } = await db.from(t).delete().eq("sample", true).select("id");
      if (!error) { removed += data?.length ?? 0; continue; }
      // a sample product that already has an order cannot be deleted — hide it instead
      const { data: left } = await db.from(t).select("id").eq("sample", true);
      for (const r of left ?? []) {
        const { error: e2 } = await db.from(t).delete().eq("id", r.id);
        if (e2) { await db.from(t).update({ is_active: false }).eq("id", r.id); hidden++; } else removed++;
      }
    }
    const { data: c } = await db.from("company_info").select("id,about_image_url,founder_photo_url").limit(1).maybeSingle();
    if (c) {
      const patch: Record<string, null> = {};
      if (c.about_image_url?.startsWith(site)) patch.about_image_url = null;
      if (c.founder_photo_url?.startsWith(site)) patch.founder_photo_url = null;
      if (Object.keys(patch).length) await db.from("company_info").update(patch).eq("id", c.id);
    }
    await db.from("verticals").update({ image_url: null }).like("image_url", `${site}%`);
    revalidatePath("/cms", "layout");
    await setFlash({ ok: `Sample content removed (${removed} items${hidden ? `; ${hidden} sample product(s) with orders were hidden instead` : ""}). Your own content was not touched.` });
  } catch (e) { return fail(e); }
  redirect("/cms");
}
