"use client";
import { startTransition, useActionState, useState } from "react";
import type { ActionState } from "@/lib/action-state";
import { PORTAL_THEMES } from "@/lib/themes";
import { p } from "@/lib/base-path";

/** Pick the home-screen theme for one customer and apply it (this customer only). */
export function ThemePicker({ action, id, current, inherited }: { action: (s: ActionState, f: FormData) => Promise<ActionState>; id: string; current: string | null; inherited?: string | null }) {
  const [sel, setSel] = useState<string>(current ?? "");
  const [state, run, pending] = useActionState<ActionState, FormData>(action, {});
  const shown = sel || inherited || "a";
  const apply = () => { const f = new FormData(); f.set("id", id); f.set("theme", sel); startTransition(() => run(f)); };
  return (
    <div>
      <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill,minmax(190px,1fr))", gap: 12 }}>
        {PORTAL_THEMES.map((t) => {
          const on = (sel || inherited || "a") === t.id;
          return (
            <button key={t.id} type="button" onClick={() => setSel(t.id)} title={t.note}
              style={{ textAlign: "left", padding: 6, borderRadius: 12, background: "#fff", cursor: "pointer", border: on ? "2px solid #7C3AED" : "1px solid var(--border)", boxShadow: on ? "0 0 0 3px rgba(124,58,237,.15)" : "none" }}>
              <img src={p(`/themes/${t.id}.jpg`)} alt="" loading="lazy" style={{ width: "100%", borderRadius: 8, display: "block", aspectRatio: "480/275", objectFit: "cover" }} />
              <div style={{ padding: "6px 4px 2px", fontSize: 13 }}><b>{t.id.toUpperCase()} · {t.name}</b>
                {t.id === (current ?? "") && <span className="muted"> — in use</span>}<br /><small className="muted">{t.note}</small></div>
            </button>
          );
        })}
      </div>
      <div className="row" style={{ marginTop: 12, gap: 8, alignItems: "center" }}>
        <button type="button" className="btn" disabled={pending || sel === (current ?? "")} onClick={apply}>{pending ? "Applying…" : `Apply ${PORTAL_THEMES.find((t) => t.id === shown)?.name ?? ""} to this customer`}</button>
        {current && <button type="button" className="btn secondary" disabled={pending} onClick={() => { setSel(""); const f = new FormData(); f.set("id", id); f.set("theme", ""); startTransition(() => run(f)); }}>Back to standard</button>}
      </div>
      {state.ok && <p className="alert ok" style={{ margin: "8px 0 0" }}>{state.ok}</p>}
      {state.error && <p className="alert error" style={{ margin: "8px 0 0" }}>{state.error}</p>}
    </div>
  );
}
