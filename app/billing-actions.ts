"use server";
import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { z } from "zod";
import { assertManager } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import type { ActionState } from "@/lib/action-state";
import { setFlash } from "@/lib/flash";

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
  lut_no: opt(60), bank_details: opt(600), upi_id: opt(80), terms: opt(1000),
  payment_days: z.string().trim().transform(Number).refine((v) => Number.isInteger(v) && v >= 0 && v <= 120, "Payment days: 0 to 120"),
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
    const items = form.getAll("product").map(String).map((code) => ({ product_code: code, seats: Number(form.get(`seats_${code}`) || 0) }));
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
    await setFlash({ ok: `Invoice ${num} issued. Share the pay link with the customer, or mark it paid when the money arrives.` });
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
    await rpc("mark_invoice_paid", { p_invoice: id, p_reference: form.get("reference"), p_date: form.get("paid_on") || null });
    await setFlash({ ok: "Payment recorded. The invoice is paid and the customer's licences are renewed for the paid period." });
  } catch (e) { return fail(e); }
  redirect(`/invoices/${id}`);
}
