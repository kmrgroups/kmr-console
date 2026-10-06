"use server";
import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { z } from "zod";
import { assertManager } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { createAdminClient } from "@/lib/supabase/admin";
import type { ActionState } from "@/lib/action-state";
import { setFlash } from "@/lib/flash";
import { mailInvoiceIssued, mailPaymentReceived, mailPaymentRejected } from "@/lib/notify";

const fail = (e: unknown): ActionState => ({ error: (e as Error).message });
const opt = (max = 300) => z.string().trim().max(max).optional().transform((v) => v || null);
const money = z.string().trim().regex(/^\d+(\.\d{1,2})?$/, "Enter an amount like 1500 or 1500.50").transform(Number);

// ---------- price list ----------
const priceSchema = z.object({
  product_code: z.string().min(2),
  period: z.enum(["month", "year"]),
  currency: z.string().trim().toUpperCase().regex(/^[A-Z]{3}$/, "Currency: 3-letter code, e.g. INR, USD"),
  unit_amount: money,
  min_seats: z.string().trim().optional().transform((v) => (v ? Number(v) : 1)).refine((v) => Number.isInteger(v) && v >= 1 && v <= 100000, "Minimum must be a whole number, 1 or more"),
  note: opt(),
  active: z.string().optional().transform((v) => v !== "off"),
});

export async function savePrice(_: ActionState, form: FormData): Promise<ActionState> {
  try {
    await assertManager();
    const parsed = priceSchema.safeParse(Object.fromEntries(form));
    if (!parsed.success) return { error: parsed.error.issues[0].message };
    const supabase = await createClient();
    const { error } = await supabase.from("prices").upsert({ ...parsed.data, updated_at: new Date().toISOString() }, { onConflict: "product_code,period,currency" });
    if (error) return { error: error.message };
    revalidatePath("/billing");
    return { ok: "Price saved." };
  } catch (e) { return fail(e); }
}

export async function deletePrice(form: FormData) {
  await assertManager();
  const supabase = await createClient();
  await supabase.from("prices").delete().eq("id", String(form.get("id")));
  revalidatePath("/billing");
}

// ---------- seller details ----------
const settingsSchema = z.object({
  legal_name: z.string().trim().min(2, "Legal name is required").max(200),
  gstin: z.string().trim().toUpperCase().regex(/^[0-9]{2}[A-Z0-9]{13}$/, "GSTIN: 15 characters, e.g. 29ABCDE1234F1Z5").or(z.literal("")).transform((v) => v || null),
  pan: opt(20), address: opt(500), city: opt(80), state: opt(80), postal_code: opt(20), email: opt(120), phone: opt(40),
  state_code: z.string().trim().regex(/^\d{2}$/, "State code: 2 digits, e.g. 29 for Karnataka").or(z.literal("")).transform((v) => v || null),
  invoice_prefix: z.string().trim().toUpperCase().regex(/^[A-Z0-9-]{1,10}$/, "Invoice prefix: up to 10 letters, digits or dashes"),
  sac_code: z.string().trim().regex(/^\d{4,8}$/, "SAC: 4–8 digits"),
  gst_rate: z.string().trim().transform(Number).refine((v) => v >= 0 && v <= 40, "GST rate between 0 and 40"),
  lut_no: opt(60), bank_details: opt(600), terms: opt(1000),
  upi_id: z.string().trim().toLowerCase().regex(/^[a-z0-9._-]{2,256}@[a-z][a-z0-9.-]{1,64}$/, "UPI ID looks like kmrgroups@fbl").or(z.literal("")).transform((v) => v || null),
  bank_account_name: opt(120), bank_name: opt(80), bank_branch: opt(120), bank_account_type: opt(40),
  bank_account_no: z.string().trim().regex(/^\d{6,20}$/, "Account number: digits only").or(z.literal("")).transform((v) => v || null),
  bank_ifsc: z.string().trim().toUpperCase().regex(/^[A-Z]{4}0[A-Z0-9]{6}$/, "IFSC: 11 characters, e.g. FDRL0002514").or(z.literal("")).transform((v) => v || null),
  bank_swift: z.string().trim().toUpperCase().regex(/^[A-Z0-9]{8}([A-Z0-9]{3})?$/, "SWIFT: 8 or 11 characters").or(z.literal("")).transform((v) => v || null),
  payment_days: z.string().trim().transform(Number).refine((v) => Number.isInteger(v) && v >= 0 && v <= 120, "Payment days: 0 to 120"),
  trade_name: opt(200), constitution: opt(60), website: opt(120), signatory_name: opt(120), signatory_title: opt(80),
  udyam_no: z.string().trim().toUpperCase().regex(/^UDYAM-[A-Z]{2}-\d{2}-\d{7}$/, "Udyam number looks like UDYAM-PY-03-0058991").or(z.literal("")).transform((v) => v || null),
  msme_category: z.enum(["Micro", "Small", "Medium", ""]).transform((v) => v || null),
  show_seal: z.string().optional().transform((v) => v === "on"),
  show_msme_note: z.string().optional().transform((v) => v === "on"),
});

export async function saveBillingSettings(_: ActionState, form: FormData): Promise<ActionState> {
  try {
    await assertManager();
    const parsed = settingsSchema.safeParse(Object.fromEntries(form));
    if (!parsed.success) return { error: parsed.error.issues[0].message };
    const d = parsed.data;
    if (d.gstin && d.state_code && d.gstin.slice(0, 2) !== d.state_code) return { error: `The GSTIN starts with ${d.gstin.slice(0, 2)}, but the state code is ${d.state_code}.` };
    const supabase = await createClient();
    const { error } = await supabase.from("billing_settings").update({ ...d, state_code: d.state_code ?? d.gstin?.slice(0, 2) ?? null, updated_at: new Date().toISOString() }).eq("id", true);
    if (error) return { error: error.message };
    revalidatePath("/billing");
    return { ok: "Seller details saved. New invoices use them when issued." };
  } catch (e) { return fail(e); }
}

// ---------- invoices ----------
async function rpc(name: string, args: Record<string, unknown>) {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc(name, args);
  if (error) throw new Error(error.message);
  return data;
}

export async function createInvoice(_: ActionState, form: FormData): Promise<ActionState> {
  let id = "";
  try {
    await assertManager();
    const customer = String(form.get("customer_id") ?? "");
    // each ticked product carries the features chosen for it; the price is the sum of those features
    const items = form.getAll("product").map(String).map((code) => ({ product_code: code, seats: Number(form.get(`seats_${code}`) || 0), features: form.getAll(`feat_${code}`).map(String).filter(Boolean) }));
    if (!items.length) return { error: "Tick at least one product to bill." };
    id = await rpc("create_invoice", { p_customer: customer, p_period: form.get("period"), p_from: form.get("from") || null, p_items: items, p_notes: form.get("notes") || null });
    await setFlash({ ok: "Draft invoice created. Check it, add any extra line, then Issue." });
  } catch (e) { return fail(e); }
  redirect(`/invoices/${id}`);
}

export async function addInvoiceLine(_: ActionState, form: FormData): Promise<ActionState> {
  try {
    await assertManager();
    const id = String(form.get("invoice_id"));
    const qty = Number(form.get("qty")), rate = Number(form.get("unit_amount"));
    await rpc("add_invoice_line", { p_invoice: id, p_description: form.get("description"), p_qty: qty, p_unit_amount: rate });
    revalidatePath(`/invoices/${id}`);
    return { ok: "Line added." };
  } catch (e) { return fail(e); }
}

export async function removeInvoiceLine(form: FormData) {
  await assertManager();
  const id = String(form.get("invoice_id"));
  await rpc("remove_invoice_line", { p_invoice: id, p_line: Number(form.get("line_id")) });
  revalidatePath(`/invoices/${id}`);
}

export async function issueInvoice(_: ActionState, form: FormData): Promise<ActionState> {
  const id = String(form.get("invoice_id"));
  try {
    await assertManager();
    const num = await rpc("issue_invoice", { p_invoice: id });
    await mailInvoiceIssued(id);
    await setFlash({ ok: `Invoice ${num} issued and emailed to the customer's contact (with the pay link). Mark it paid when the money arrives.` });
  } catch (e) { return fail(e); }
  redirect(`/invoices/${id}`);
}

export async function discardInvoice(_: ActionState, form: FormData): Promise<ActionState> {
  const id = String(form.get("invoice_id")), customer = String(form.get("customer_id"));
  try {
    await assertManager();
    await rpc("discard_invoice", { p_invoice: id });
    await setFlash({ ok: "Draft discarded." });
  } catch (e) { return fail(e); }
  redirect(`/customers/${customer}`);
}

export async function cancelInvoice(_: ActionState, form: FormData): Promise<ActionState> {
  const id = String(form.get("invoice_id"));
  try {
    await assertManager();
    await rpc("cancel_invoice", { p_invoice: id, p_reason: form.get("reason") });
    await setFlash({ ok: "Invoice cancelled. Its number stays in the series." });
  } catch (e) { return fail(e); }
  redirect(`/invoices/${id}`);
}

export async function markInvoicePaid(_: ActionState, form: FormData): Promise<ActionState> {
  const id = String(form.get("invoice_id"));
  try {
    await assertManager();
    await rpc("mark_invoice_paid", { p_invoice: id, p_reference: form.get("reference"), p_date: form.get("paid_on") || null, p_method: form.get("pay_method") || "neft" });
    await mailPaymentReceived(id);
    await setFlash({ ok: "Payment recorded. The invoice is paid and the customer's licences are renewed for the paid period." });
  } catch (e) { return fail(e); }
  redirect(`/invoices/${id}`);
}

export async function confirmPayment(_: ActionState, form: FormData): Promise<ActionState> {
  const id = String(form.get("invoice_id"));
  try {
    await assertManager();
    await rpc("confirm_payment", { p_payment: form.get("payment_id") });
    await mailPaymentReceived(id);
    await setFlash({ ok: "Payment confirmed. The invoice is paid and the customer's licences are renewed for the paid period." });
  } catch (e) { return fail(e); }
  redirect(`/invoices/${id}`);
}

export async function rejectPayment(_: ActionState, form: FormData): Promise<ActionState> {
  const id = String(form.get("invoice_id"));
  try {
    await assertManager();
    await rpc("reject_payment", { p_payment: form.get("payment_id"), p_reason: form.get("reason") });
    await mailPaymentRejected(id, String(form.get("reason") ?? ""));
    await setFlash({ ok: "Payment report rejected. The customer sees the reason on the pay link." });
  } catch (e) { return fail(e); }
  redirect(`/invoices/${id}`);
}

/** Company seal or signature for invoices — kept in the private kmr-billing bucket, never public. */
export async function uploadBillingImage(_: ActionState, form: FormData): Promise<ActionState> {
  try {
    await assertManager();
    const kind = String(form.get("kind"));
    if (kind !== "seal" && kind !== "signature" && kind !== "letterhead") return { error: "Unknown image." };
    const file = form.get("image");
    if (!(file instanceof File) || !file.size) return { error: "Choose an image file." };
    if (!["image/png", "image/jpeg", "image/webp"].includes(file.type)) return { error: "Use a PNG (best, with a transparent background), JPG or WebP image." };
    if (file.size > (kind === "letterhead" ? 5 : 2) * 1024 * 1024) return { error: `The image must be under ${kind === "letterhead" ? 5 : 2} MB.` };
    if (kind === "letterhead" && file.type === "image/webp") return { error: "Use a PNG or JPG for the letterhead (A4 portrait, e.g. 1240 × 1754 px)." };
    const path = `${kind}/${Date.now()}.${file.type === "image/png" ? "png" : file.type === "image/webp" ? "webp" : "jpg"}`;
    const { error: upErr } = await createAdminClient().storage.from("kmr-billing").upload(path, file, { contentType: file.type });
    if (upErr) return { error: upErr.message };
    // Older files are kept: invoices already issued still point to the seal / signature they were issued with
    const supabase = await createClient();
    const { error } = await supabase.from("billing_settings").update({ [`${kind}_path`]: path, updated_at: new Date().toISOString() }).eq("id", true);
    if (error) return { error: error.message };
    revalidatePath("/billing");
    return { ok: kind === "letterhead" ? "Letterhead saved. Every quotation PDF uses it from now on." : `${kind === "seal" ? "Seal" : "Signature"} saved. New invoices use it when issued.` };
  } catch (e) { return fail(e); }
}

export async function removeBillingImage(form: FormData) {
  await assertManager();
  const kind = String(form.get("kind"));
  if (kind !== "seal" && kind !== "signature" && kind !== "letterhead") return;
  const supabase = await createClient();
  await supabase.from("billing_settings").update({ [`${kind}_path`]: null, updated_at: new Date().toISOString() }).eq("id", true);
  revalidatePath("/billing");
}

// ---------- app features and their prices (Prices & invoices › Apps & features) ----------
const amt = (label: string) => z.string().trim().regex(/^\d+(\.\d{1,2})?$/, `${label}: enter an amount like 250 or 250.50`).transform(Number);
const featureSchema = z.object({
  id: z.string().uuid().optional().or(z.literal("")).transform((v) => v || undefined),
  product_code: z.string().min(2),
  name: z.string().trim().min(2, "Enter the feature name").max(120),
  detail: opt(300),
  price_month: amt("Monthly price"),
  price_year: z.string().trim().optional().transform((v) => v || ""),
  setup_fee: z.string().trim().optional().transform((v) => v || "0").pipe(amt("Set-up fee")),
  sort_order: z.string().optional().transform((v) => (v ? Number(v) : 100)),
  is_core: z.string().optional().transform((v) => v === "on"),
  active: z.string().optional().transform((v) => v !== "off"),
});

export async function saveFeature(_: ActionState, form: FormData): Promise<ActionState> {
  try {
    await assertManager();
    const parsed = featureSchema.safeParse(Object.fromEntries(form));
    if (!parsed.success) return { error: parsed.error.issues[0].message };
    const { id, price_year, ...rest } = parsed.data;
    // yearly price left blank = ten months' price (two months free)
    const year = price_year === "" ? Math.round(rest.price_month * 10 * 100) / 100 : Number(price_year);
    if (!Number.isFinite(year) || year < 0) return { error: "Yearly price: enter an amount like 2500." };
    const supabase = await createClient();
    const row = { ...rest, price_year: year, updated_at: new Date().toISOString() };
    const { error } = id ? await supabase.from("app_features").update(row).eq("id", id) : await supabase.from("app_features").insert(row);
    if (error) return { error: error.message.includes("duplicate") ? "This app already has a feature with that name." : error.message };
    revalidatePath("/billing");
    return { ok: id ? "Feature saved. The app's full price now follows its features." : "Feature added." };
  } catch (e) { return fail(e); }
}

export async function deleteFeature(form: FormData) {
  await assertManager();
  const supabase = await createClient();
  await supabase.from("app_features").delete().eq("id", String(form.get("id")));
  revalidatePath("/billing");
}
