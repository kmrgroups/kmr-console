"use server";
import { revalidatePath } from "next/cache";
import { assertStaff } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { web } from "@/lib/manage-server";
import type { ActionState } from "@/lib/action-state";

const fail = (e: unknown): ActionState => ({ error: (e as Error).message });
const SHOP_ROLES = ["owner", "admin", "sales"];

/** Shop orders: the staff member's own login calls the website's order functions, which check the Console role. */
async function orderRpc(fn: string, args: Record<string, unknown>) {
  const staff = await assertStaff();
  if (!SHOP_ROLES.includes(staff.role)) throw new Error("Only owners, administrators and sales staff can handle orders.");
  const supabase = await createClient();
  const { data, error } = await supabase.schema("public").rpc(fn, args);
  if (error) throw new Error(error.message);
  revalidatePath("/website/orders");
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

/** Publish ticked Operations Master parts to the website (hidden until reviewed). */
export async function publishFromOps(_: ActionState, form: FormData): Promise<ActionState> {
  try {
    await assertStaff();
    const codes = form.getAll("code").map(String);
    const supabase = await createClient();
    const { data, error } = await supabase.rpc("publish_ops_products", { p_customer: form.get("customer_id"), p_codes: codes, p_business: form.get("business") || "shop" });
    if (error) return { error: error.message };
    revalidatePath("/manage/products");
    return { ok: `${data.added} new product${data.added === 1 ? "" : "s"} added (hidden until you set the price, stock and photo and tick “Show on the website”)${data.refreshed ? `, ${data.refreshed} refreshed` : ""}. Open Website → Products to finish them.` };
  } catch (e) { return fail(e); }
}

/** Stock movement: + in, − out. */
export async function addStockMove(_: ActionState, form: FormData): Promise<ActionState> {
  try {
    const staff = await assertStaff();
    if (!SHOP_ROLES.includes(staff.role)) return { error: "Only owners, administrators and sales staff can record stock." };
    const type = String(form.get("transaction_type"));
    const OUT = ["sales_dispatch", "production_consumption"];
    const qty = Math.abs(Number(form.get("quantity")));
    if (!qty) return { error: "Enter the quantity." };
    const signed = type === "adjustment" ? Number(form.get("quantity")) : OUT.includes(type) ? -qty : qty;
    const { error } = await web().from("stock_transactions").insert({
      item_id: form.get("item_id"), warehouse_id: form.get("warehouse_id"), transaction_type: type, quantity: signed,
      unit_cost: form.get("unit_cost") ? Number(form.get("unit_cost")) : null, reference_note: String(form.get("reference_note") || "") || null,
      transaction_date: form.get("transaction_date") || undefined,
    });
    if (error) return { error: error.message };
    revalidatePath("/operations/stock");
    return { ok: `Recorded: ${signed > 0 ? "+" : ""}${signed}.` };
  } catch (e) { return fail(e); }
}
