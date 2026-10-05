"use server";
import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { z } from "zod";
import { assertManager, assertStaff } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import type { ActionState } from "@/lib/action-state";
import { BASIS, totals, type QuoteInput } from "@/lib/quote";

const fail = (e: unknown): ActionState => ({ error: (e as Error).message });
const basis = z.enum(Object.keys(BASIS) as [keyof typeof BASIS, ...(keyof typeof BASIS)[]]);
const txt = (max: number) => z.string().trim().max(max).optional().default("");
const num = z.coerce.number().finite();

const quoteSchema = z.object({
  id: z.string().uuid().optional(),
  customer_id: z.string().uuid().nullable().optional(),
  to_name: z.string().trim().min(2, "Enter the customer's company name").max(200),
  to_attn: txt(200), to_address: txt(500), to_gstin: txt(15), to_email: txt(200), to_phone: txt(40),
  subject: z.string().trim().min(3, "Enter the subject of the quotation").max(300),
  intro: txt(3000),
  scope: z.array(z.object({ module: z.string().trim().max(200), capability: z.string().trim().max(600) })).max(60)
    .transform((r) => r.filter((x) => x.module || x.capability)),
  lines: z.array(z.object({
    particulars: z.string().trim().max(200), detail: z.string().trim().max(400).optional().default(""),
    basis, qty: num.min(0).max(1e7), rate: num.min(0).max(1e10), months: num.min(1).max(120).optional().default(1),
    product_code: z.string().nullable().optional(),
  })).max(80).transform((r) => r.filter((x) => x.particulars))
    .refine((r) => r.length > 0, "Add at least one priced line"),
  includes: txt(3000), terms: txt(6000),
  discount_pct: num.min(0).max(100).default(0), gst_rate: num.min(0).max(40).default(18),
  quote_date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/), valid_until: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).nullable().optional(),
  notes: txt(2000),
});

/** Saves a quotation (new or existing); the number is given on the first save. */
export async function saveQuote(input: QuoteInput): Promise<{ error?: string; id?: string; number?: string }> {
  try {
    const me = await assertStaff();
    const parsed = quoteSchema.safeParse(input);
    if (!parsed.success) return { error: parsed.error.issues[0].message };
    const q = parsed.data, t = totals(q);
    const supabase = await createClient();
    const row = { ...q, ...t, updated_by: me.email, updated_at: new Date().toISOString(), valid_until: q.valid_until || null };
    delete (row as { id?: string }).id;
    if (q.id) {
      const { data, error } = await supabase.from("quotes").update(row).eq("id", q.id).select("id,number").single();
      if (error) return { error: error.message };
      revalidatePath("/billing"); revalidatePath(`/quotes/${q.id}`);
      return { id: data.id, number: data.number };
    }
    const { data: number, error: nErr } = await supabase.rpc("next_quote_number");
    if (nErr) return { error: nErr.message };
    const { data, error } = await supabase.from("quotes").insert({ ...row, number, created_by: me.email }).select("id,number").single();
    if (error) return { error: error.message };
    revalidatePath("/billing");
    return { id: data.id, number: data.number };
  } catch (e) { return { error: (e as Error).message }; }
}

export async function setQuoteStatus(_: ActionState, form: FormData): Promise<ActionState> {
  try {
    await assertStaff();
    const status = z.enum(["draft", "sent", "accepted", "declined", "expired"]).parse(form.get("status"));
    const id = z.string().uuid().parse(form.get("id"));
    const supabase = await createClient();
    const { error } = await supabase.from("quotes").update({ status, updated_at: new Date().toISOString() }).eq("id", id);
    if (error) return { error: error.message };
    revalidatePath("/billing"); revalidatePath(`/quotes/${id}`);
    return { ok: `Marked as ${status}.` };
  } catch (e) { return fail(e); }
}

export async function deleteQuote(_: ActionState, form: FormData): Promise<ActionState> {
  try {
    await assertManager();
    const id = z.string().uuid().parse(form.get("id"));
    const supabase = await createClient();
    const { error } = await supabase.from("quotes").delete().eq("id", id);
    if (error) return { error: error.message };
    revalidatePath("/billing");
  } catch (e) { return fail(e); }
  redirect("/billing?tab=quotes");
}

// ---------- costing catalogue ----------
const costSchema = z.object({
  id: z.string().uuid().optional().or(z.literal("").transform(() => undefined)),
  product_code: z.string().optional().transform((v) => v || null),
  name: z.string().trim().min(2, "Enter a name").max(160),
  detail: z.string().trim().max(400).optional().transform((v) => v || null),
  basis,
  amount: z.string().trim().regex(/^\d+(\.\d{1,2})?$/, "Enter an amount like 15000").transform(Number),
  default_qty: z.string().trim().optional().transform((v) => (v ? Number(v) : 1)).refine((v) => v > 0, "Default quantity must be more than 0"),
  include_by_default: z.string().optional().transform((v) => v === "on"),
  sort_order: z.string().optional().transform((v) => (v ? Number(v) : 100)),
  active: z.string().optional().transform((v) => v !== "off"),
});

export async function saveCostItem(_: ActionState, form: FormData): Promise<ActionState> {
  try {
    await assertManager();
    const parsed = costSchema.safeParse(Object.fromEntries(form));
    if (!parsed.success) return { error: parsed.error.issues[0].message };
    const { id, ...row } = parsed.data;
    const supabase = await createClient();
    const { error } = id
      ? await supabase.from("cost_items").update({ ...row, updated_at: new Date().toISOString() }).eq("id", id)
      : await supabase.from("cost_items").insert(row);
    if (error) return { error: error.message };
    revalidatePath("/billing");
    return { ok: id ? "Cost item saved." : "Cost item added." };
  } catch (e) { return fail(e); }
}

export async function deleteCostItem(form: FormData) {
  await assertManager();
  const supabase = await createClient();
  await supabase.from("cost_items").delete().eq("id", String(form.get("id")));
  revalidatePath("/billing");
}

const quoteSettings = z.object({
  quote_prefix: z.string().trim().min(1).max(20),
  quote_validity_days: z.coerce.number().int().min(1).max(180),
  quote_includes: z.string().max(3000).optional().default(""),
  quote_terms: z.string().max(6000).optional().default(""),
});
export async function saveQuoteSettings(_: ActionState, form: FormData): Promise<ActionState> {
  try {
    await assertManager();
    const parsed = quoteSettings.safeParse(Object.fromEntries(form));
    if (!parsed.success) return { error: parsed.error.issues[0].message };
    const supabase = await createClient();
    const { error } = await supabase.from("billing_settings").update({ ...parsed.data, updated_at: new Date().toISOString() }).eq("id", true);
    if (error) return { error: error.message };
    revalidatePath("/billing");
    return { ok: "Quotation defaults saved." };
  } catch (e) { return fail(e); }
}
