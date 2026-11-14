"use server";
import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { z } from "zod";
import { assertManager } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { ensureLogin } from "@/lib/provision";
import { env } from "@/lib/env";
import type { ActionState } from "@/lib/action-state";
import { setFlash } from "@/lib/flash";
import { enableTool } from "@/app/actions";

const opt = z.string().trim().max(300).optional().transform((v) => v || null);
const customerSchema = z.object({
  name: z.string().trim().min(2, "Company name is required").max(120),
  legal_name: opt, tax_id: opt, address: opt, city: opt, state: opt, postal_code: opt, source: opt, notes: z.string().trim().max(2000).optional().transform((v) => v || null),
  country: z.string().trim().toUpperCase().regex(/^[A-Z]{2}$/, "Country: 2-letter code, e.g. IN, US, DE"),
  currency: z.string().trim().toUpperCase().regex(/^[A-Z]{3}$/, "Currency: 3-letter code, e.g. INR, USD"),
  time_zone: z.string().trim().min(3).max(60),
  contact_name: opt, contact_phone: opt,
  contact_email: z.string().trim().toLowerCase().email("Enter a valid contact email").or(z.literal("")).transform((v) => v || null),
  status: z.enum(["lead", "pilot", "active", "inactive"]),
});
const ST = ["trial", "pilot", "active", "suspended", "expired", "cancelled"];
const DAY = /^\d{4}-\d{2}-\d{2}$/;

/**
 * One save for everything on the screen: the company (when new), which apps are on, each app's status, end date (renewal),
 * user limit and the features it may use.
 */
export async function saveSetup(_: ActionState, form: FormData): Promise<ActionState> {
  let id = String(form.get("customer_id") ?? "");
  const isNew = !id;
  const notes: string[] = [];
  try {
    const staff = await assertManager();
    const supabase = await createClient();
    if (isNew) {
      const parsed = customerSchema.safeParse(Object.fromEntries(form));
      if (!parsed.success) return { error: parsed.error.issues[0].message };
      const { data, error } = await supabase.from("customers").insert({ ...parsed.data, created_by: staff.user_id }).select("id,slug").single();
      if (error) return { error: error.message };
      id = data.id;
      const email = parsed.data.contact_email;
      if (email) {
        try {
          const login = await ensureLogin(email, parsed.data.contact_name || parsed.data.name);
          const url = `${env.platformUrl}/it/app/${data.slug ?? ""}`;
          notes.push(login.password
            ? `Customer created. Portal sign-in for ${parsed.data.contact_name || email}: ${url} · ${email} · temporary password ${login.password} (shown only now).`
            : `Customer created. ${email} already has a KMR login: ${url}.`);
        } catch (e) { notes.push(`Customer created, but the portal login could not be made: ${(e as Error).message}.`); }
      } else notes.push("Customer created. Add a contact email so the apps can have an administrator.");
    }
    const { data: cust } = await supabase.from("customers").select("id,name,contact_name,contact_email,status").eq("id", id).single();
    if (!cust) return { error: "Customer not found." };
    const { data: lic } = await supabase.from("licences").select("product_code,status").eq("customer_id", id);
    const have = new Set((lic ?? []).map((l) => l.product_code));
    const codes = String(form.get("codes") ?? "").split(",").map((x) => x.trim()).filter(Boolean);
    let changed = 0;
    for (const code of codes) {
      const st = String(form.get(`st_${code}`) ?? "off");
      const until = String(form.get(`until_${code}`) ?? "");
      const seats = String(form.get(`seats_${code}`) ?? "").trim();
      if (until && !DAY.test(until)) { notes.push(`${code}: the end date is not valid.`); continue; }
      if (seats && !(Number.isInteger(Number(seats)) && Number(seats) > 0)) { notes.push(`${code}: the user limit must be a whole number.`); continue; }
      if (!have.has(code)) {
        if (st === "off") continue;
        if (!cust.contact_email) { notes.push(`${code}: not switched on — add the contact email first (it becomes the app's administrator).`); continue; }
        const fd = new FormData();
        fd.set("customer_id", id); fd.set("product_code", code); fd.set("workspace", cust.name);
        fd.set("admin_name", cust.contact_name || cust.name); fd.set("admin_email", cust.contact_email);
        fd.set("status", ["trial", "pilot", "active"].includes(st) ? st : "trial"); fd.set("valid_until", until); fd.set("seats", seats);
        const r = await enableTool({}, fd);
        if (r.error) { notes.push(`${code}: ${r.error}`); continue; }
        if (r.ok) notes.push(r.ok);
        changed++;
        if (!["trial", "pilot", "active"].includes(st)) await supabase.from("licences").update({ status: st }).eq("customer_id", id).eq("product_code", code);
      } else {
        const upd = st === "off" ? { status: "suspended" } : { status: ST.includes(st) ? st : "active", valid_until: until || null, seats: seats ? Number(seats) : null };
        const { error } = await supabase.from("licences").update(upd).eq("customer_id", id).eq("product_code", code);
        if (error) { notes.push(`${code}: ${error.message}`); continue; }
        changed++;
      }
      // features this app may use (core features are always kept)
      if (form.get(`scope_${code}`) !== null) {
        let features: string[] | null = null;
        if (form.get(`scope_${code}`) === "only") {
          const keys = form.getAll(`ft_${code}`).map(String);
          const { data: core } = await supabase.from("app_features").select("key").eq("product_code", code).eq("is_core", true).eq("active", true);
          features = Array.from(new Set([...keys, ...((core ?? []) as { key: string }[]).map((x) => x.key)]));
        }
        const { error } = await supabase.from("licences").update({ features, updated_at: new Date().toISOString() }).eq("customer_id", id).eq("product_code", code);
        if (error) notes.push(`${code} features: ${error.message.includes("features") ? "run 0051_feature_access.sql first." : error.message}`);
      }
    }
    if (!isNew) notes.push(changed ? `Saved. ${changed} app${changed === 1 ? "" : "s"} updated; the apps apply it within a minute.` : "Saved.");
    revalidatePath(`/customers/${id}`);
    if (!isNew) return { ok: notes.join("  ") };
  } catch (e) { return { error: (e as Error).message }; }
  await setFlash({ ok: notes.join("  ") });
  redirect(`/customers/${id}`);
}
