"use server";
import { revalidatePath } from "next/cache";
import { assertManager } from "@/lib/auth";
import type { ActionState } from "@/lib/action-state";
import { resetDemoWorkspace } from "@/lib/test-data";

/** Switch every app on in the KMR demo workspace and reload each app's sample data from scratch. */
export async function reloadDemoApps(_: ActionState): Promise<ActionState> {
  try {
    await assertManager();
    const r = await resetDemoWorkspace();
    revalidatePath("/apps");
    const n = r && typeof r === "object" ? Object.keys(r as object).length : 0;
    return { ok: `Every app is switched on in the demo workspace and its sample data was reloaded${n ? ` (${n} workspaces)` : ""}.` };
  } catch (e) { return { error: (e as Error).message }; }
}
