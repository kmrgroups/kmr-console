"use server";
import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { assertManager } from "@/lib/auth";
import { setFlash } from "@/lib/flash";
import type { ActionState } from "@/lib/action-state";
import { DEMO, FLUSH_PARTS, flushPlatform, loadDemoEverywhere, removeDemoEverywhere, restoreSettings, saveFullBackup } from "@/lib/test-data";

const owner = async () => { const s = await assertManager(); if (s.role !== "owner") throw new Error("Only the owner can use Test data."); return s; };
const fail = (e: unknown): ActionState => ({ error: (e as Error).message });
const lines = (steps: { part: string; ok: boolean; note: string }[]) => steps.map((s) => `${s.ok ? "✓" : "✗"} ${s.part}: ${s.note}`).join("  ·  ");

export async function loadDemo(_: ActionState): Promise<ActionState> {
  try {
    await owner();
    const { steps, password } = await loadDemoEverywhere();
    revalidatePath("/", "layout");
    await setFlash({ ok: `Demo data loaded. ${lines(steps)}.  ONE LOGIN FOR EVERY APP — email ${DEMO.email} · password ${password} (shown only now). Customer portal: www.kmr-groups.com/it/app/${DEMO.slug}` });
  } catch (e) { return fail(e); }
  redirect("/test-data");
}

export async function removeDemo(_: ActionState): Promise<ActionState> {
  try {
    await owner();
    const steps = await removeDemoEverywhere();
    revalidatePath("/", "layout");
    await setFlash({ ok: `Demo data removed. ${lines(steps)}.` });
  } catch (e) { return fail(e); }
  redirect("/test-data");
}

export async function takeFullBackup(_: ActionState): Promise<ActionState> {
  try {
    await owner();
    const b = await saveFullBackup("manual");
    revalidatePath("/test-data");
    return { ok: `Full backup saved (${Math.round(b.bytes / 1024)} KB). Download it from the list below.` };
  } catch (e) { return fail(e); }
}

export async function uploadSettings(_: ActionState, form: FormData): Promise<ActionState> {
  try {
    await owner();
    const f = form.get("file");
    if (!(f instanceof File) || !f.size) return { error: "Choose the settings file (.json) first." };
    if (f.size > 5 * 1024 * 1024) return { error: "That file is too large to be a settings file." };
    let json: unknown;
    try { json = JSON.parse(await f.text()); } catch { return { error: "That file is not valid JSON." }; }
    const r = await restoreSettings(json);
    const total = Object.values(r).reduce((a, b) => a + Number(b), 0);
    revalidatePath("/", "layout");
    return { ok: `Settings restored: ${total} records in ${Object.keys(r).length} tables (products, prices, seller details, company profile, website pages and content). Nothing else was changed.` };
  } catch (e) { return fail(e); }
}

export async function cleanOut(_: ActionState, form: FormData): Promise<ActionState> {
  try {
    await owner();
    if (String(form.get("confirm") ?? "").trim().toUpperCase() !== "FLUSH") return { error: "Type FLUSH in the box to confirm." };
    const parts = FLUSH_PARTS.map((p) => p.key).filter((k) => form.get(k) === "on");
    if (!parts.length) return { error: "Tick at least one thing to remove." };
    const { backup, result } = await flushPlatform(parts);
    revalidatePath("/", "layout");
    const said = Object.entries(result).map(([k, v]) => `${k.replace(/_/g, " ")}: ${v}`).join(" · ");
    await setFlash({ ok: `Cleaned out. ${said}. A full backup taken just before is listed below (${backup.split("/").pop()}).` });
  } catch (e) { return fail(e); }
  redirect("/test-data");
}
