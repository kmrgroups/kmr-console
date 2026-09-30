"use server";
import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { assertStaff } from "@/lib/auth";
import { resourceByKey, type Field } from "@/lib/manage";
import { canEdit, MEDIA_BUCKET, RECORDS_BUCKET, uploadFile, web } from "@/lib/manage-server";
import type { ActionState } from "@/lib/action-state";
import { setFlash } from "@/lib/flash";

const fail = (e: unknown): ActionState => ({ error: (e as Error).message });

async function readField(f: Field, form: FormData, folder: string): Promise<unknown> {
  const raw = form.get(f.k);
  const s = typeof raw === "string" ? raw.trim() : "";
  switch (f.type) {
    case "bool": return form.get(f.k) === "on";
    case "number": case "money": {
      if (!s) return null;
      const n = Number(s.replace(/,/g, ""));
      if (!Number.isFinite(n)) throw new Error(`${f.label}: enter a number.`);
      if (f.type === "money" && n < 0) throw new Error(`${f.label} cannot be negative.`);
      return n;
    }
    case "image": case "document": {
      if (form.get(`${f.k}__clear`) === "on") return null;
      const file = form.get(`${f.k}__file`);
      if (file instanceof File && file.size) {
        if (file.size > (f.type === "image" ? 15 : 10) * 1024 * 1024) throw new Error(`${f.label}: the file is too large.`);
        return uploadFile(f.type === "image" ? MEDIA_BUCKET : RECORDS_BUCKET, folder, file);
      }
      return s || null;
    }
    case "url": if (s && !/^https?:\/\//i.test(s)) return `https://${s}`; return s || null;
    default: return s || null;
  }
}

/** Create or update one record of a website / operations table. */
export async function saveRecord(_: ActionState, form: FormData): Promise<ActionState> {
  const key = String(form.get("__resource")); const id = String(form.get("__id") || "");
  const r = resourceByKey(key);
  let newId = id;
  try {
    const staff = await assertStaff();
    if (!r) return { error: "Unknown list." };
    if (!canEdit(r, staff)) return { error: "Your role can view this but not change it." };
    const row: Record<string, unknown> = {};
    for (const f of r.fields) {
      const v = await readField(f, form, r.table);
      if (f.required && (v === null || v === "")) return { error: `${f.label} is required.` };
      row[f.k] = v;
    }
    if (["products", "hero_content", "company_info", "legal_pages"].includes(r.table)) row.updated_at = new Date().toISOString();
    const db = web().from(r.table);
    if (id) {
      const { error } = await db.update(row).eq("id", id);
      if (error) return { error: /duplicate|unique/i.test(error.message) ? "That code / SKU is already used by another record." : error.message };
    } else {
      if (r.noCreate) return { error: "New records cannot be added here." };
      const { data, error } = await db.insert(row).select("id").single();
      if (error) return { error: /duplicate|unique/i.test(error.message) ? "That code / SKU is already used by another record." : error.message };
      newId = data.id;
    }
    revalidatePath(`/manage/${key}`);
    if (id) return { ok: `Saved. The website shows the change within a minute.` };
    await setFlash({ ok: `${r.singular[0].toUpperCase()}${r.singular.slice(1)} added.` });
  } catch (e) { return fail(e); }
  redirect(`/manage/${key}/${newId}`);
}

export async function deleteRecord(_: ActionState, form: FormData): Promise<ActionState> {
  const key = String(form.get("__resource")); const id = String(form.get("__id") || "");
  const r = resourceByKey(key);
  try {
    const staff = await assertStaff();
    if (!r || r.noDelete) return { error: "This cannot be deleted." };
    if (!canEdit(r, staff)) return { error: "Your role can view this but not change it." };
    const { error } = await web().from(r.table).delete().eq("id", id);
    if (error) return { error: /foreign key|violates/i.test(error.message) ? `This ${r.singular} is used elsewhere (orders, stock …). Untick "Active" / "Show" instead of deleting.` : error.message };
    await setFlash({ ok: `${r.singular[0].toUpperCase()}${r.singular.slice(1)} deleted.` });
  } catch (e) { return fail(e); }
  redirect(`/manage/${key}`);
}
