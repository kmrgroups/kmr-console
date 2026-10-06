"use server";
import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { assertManager } from "@/lib/auth";
import { setFlash } from "@/lib/flash";
import type { ActionState } from "@/lib/action-state";
import { deleteCustomer } from "@/lib/customer-delete";

/** Owner only: delete one customer (see lib/customer-delete.ts for the safeguards). */
export async function deleteCustomerAction(_: ActionState, form: FormData): Promise<ActionState> {
  let name = "";
  try {
    const s = await assertManager();
    if (s.role !== "owner") throw new Error("Only the owner can delete a customer.");
    const id = String(form.get("id") ?? ""), typed = String(form.get("confirm") ?? "");
    const steps = await deleteCustomer(id, typed);
    name = steps.map((x) => `${x.ok ? "✓" : "✗"} ${x.part}: ${x.note}`).join("  ·  ");
  } catch (e) { return { error: (e as Error).message }; }
  revalidatePath("/", "layout");
  await setFlash({ ok: `Customer deleted. ${name}.` });
  redirect("/customers");
}
