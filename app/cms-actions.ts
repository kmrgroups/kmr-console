"use server";
import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { assertStaff } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { canEdit, sectionByKey, type Field, type Section } from "@/lib/cms";
import { MEDIA_BUCKET, PRIVATE_BUCKETS, uploadFile, web } from "@/lib/cms-server";
import type { ActionState } from "@/lib/action-state";
import { setFlash } from "@/lib/flash";

const fail = (e: unknown): ActionState => ({ error: (e as Error).message });
const cap = (s: string) => s[0].toUpperCase() + s.slice(1);
const TOUCH = ["products", "hero_content", "company_info", "legal_pages", "job_openings", "job_applications", "site_settings"];

async function readField(f: Field, form: FormData, folder: string): Promise<unknown> {
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
      if (form.get(`${f.k}__clear`) === "on") return null;
      const file = form.get(`${f.k}__file`);
      if (file instanceof File && file.size) {
        if (file.size > (f.type === "image" ? 15 : 10) * 1024 * 1024) throw new Error(`${f.label}: the file is too large.`);
        return uploadFile(f.type === "image" ? MEDIA_BUCKET : PRIVATE_BUCKETS[f.bucket ?? "records"], folder, file);
      }
      return s || null;
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
      const v = await readField(f, form, s.table);
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
    if (id) return { ok: "Saved. The website shows the change within a minute." };
    await setFlash({ ok: `${cap(s.singular)} added.` });
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
    return { ok: r === "paid" ? "Payment confirmed — the order is paid and stock reduced." : `Payment confirmed (${r}).` };
  } catch (e) { return fail(e); }
}
export async function rejectOrderPayment(_: ActionState, form: FormData): Promise<ActionState> {
  try { await orderRpc("shop_reject_payment", { p_order: form.get("id"), p_reason: form.get("reason") }); return { ok: "Report rejected — the customer sees the reason on their order page." }; }
  catch (e) { return fail(e); }
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

/** Import ticked Operations Master parts as website products (hidden until reviewed). */
export async function publishFromOps(_: ActionState, form: FormData): Promise<ActionState> {
  try {
    await assertStaff();
    const supabase = await createClient();
    const { data, error } = await supabase.rpc("publish_ops_products", { p_customer: form.get("customer_id"), p_codes: form.getAll("code").map(String), p_business: form.get("business") || "shop" });
    if (error) return { error: error.message };
    revalidatePath("/cms/products"); revalidatePath("/cms/trade");
    return { ok: `${data.added} new product${data.added === 1 ? "" : "s"} added, hidden until you set the price, stock and photo and tick “Show on the website”${data.refreshed ? `; ${data.refreshed} refreshed` : ""}.` };
  } catch (e) { return fail(e); }
}
