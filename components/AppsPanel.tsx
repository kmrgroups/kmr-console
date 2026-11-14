"use client";
import { useState } from "react";

export type PanelProduct = { code: string; name: string; description: string | null; seat_label: string | null };
export type PanelFeature = { product_code: string; key: string; name: string; detail: string | null; is_core: boolean };
export type PanelLicence = { product_code: string; status: string; valid_until: string | null; seats: number | null; features: string[] | null; product_slug?: string | null; info?: string };

const day = (d: Date) => d.toISOString().slice(0, 10);
const plus = (from: string, months: number) => { const d = new Date(from + "T00:00:00Z"); d.setUTCMonth(d.getUTCMonth() + months); return day(d); };
const OPTS: [string, string][] = [["off", "Not switched on"], ["trial", "Trial"], ["pilot", "Pilot"], ["active", "Active (paying)"], ["suspended", "Suspended (stopped, data kept)"], ["expired", "Expired"], ["cancelled", "Cancelled"]];

/** Apps, subscription end date (renewal) and features on ONE screen: no pop-ups, one Save button (the form around it). */
export function AppsPanel({ products, features, licences, today }: { products: PanelProduct[]; features: PanelFeature[]; licences: PanelLicence[]; today: string }) {
  return (
    <div className="stack" style={{ gap: 10 }}>
      <input type="hidden" name="codes" value={products.map((p) => p.code).join(",")} />
      {products.map((p) => <Row key={p.code} p={p} fl={features.filter((f) => f.product_code === p.code)} l={licences.find((x) => x.product_code === p.code)} today={today} />)}
    </div>
  );
}

function Row({ p, fl, l, today }: { p: PanelProduct; fl: PanelFeature[]; l?: PanelLicence; today: string }) {
  const [st, setSt] = useState(l ? l.status : "off");
  const [until, setUntil] = useState(l?.valid_until ?? "");
  const [scope, setScope] = useState<"all" | "only">(l?.features ? "only" : "all");
  const on = st !== "off";
  const base = until && until >= today ? until : today;
  const pick = (v: string) => { setSt(v); if (!until && !l) { if (v === "trial") setUntil(plus(today, 1)); else if (v === "pilot") setUntil(plus(today, 3)); else if (v === "active") setUntil(plus(today, 12)); } };
  const renew = (m: number) => { setUntil(plus(base, m)); if (!on || st === "expired" || st === "suspended") setSt("active"); };
  const ended = !!until && until < today;
  return (
    <div style={{ border: "1px solid var(--border)", borderRadius: 10, padding: 12, background: on ? "var(--card, #fff)" : "transparent", opacity: on ? 1 : 0.85 }}>
      <div className="spread" style={{ alignItems: "center", gap: 10, flexWrap: "wrap" }}>
        <div style={{ minWidth: 200, flex: "1 1 220px" }}><b>{p.name}</b>{ended && on && <span className="badge warn" style={{ marginLeft: 6 }}>ended {until}</span>}<br /><small className="muted">{p.description}</small>{l?.info && <><br /><small className="muted">{l.info}</small></>}</div>
        <label className="field" style={{ margin: 0, minWidth: 190 }}>Status
          <select name={`st_${p.code}`} value={st} onChange={(e) => pick(e.target.value)}>{OPTS.map(([v, t]) => <option key={v} value={v}>{t}</option>)}</select>
        </label>
      </div>
      {on && (
        <div style={{ marginTop: 10, display: "grid", gap: 10 }}>
          <div className="row" style={{ gap: 10, flexWrap: "wrap", alignItems: "flex-end" }}>
            <label className="field" style={{ margin: 0 }}>Valid until (subscription end)
              <input type="date" name={`until_${p.code}`} value={until} onChange={(e) => setUntil(e.target.value)} />
            </label>
            <div style={{ display: "flex", gap: 6, flexWrap: "wrap" }}>
              <span className="muted" style={{ alignSelf: "center", fontSize: 12.5 }}>Renew:</span>
              {[[1, "+1 month"], [3, "+3 months"], [6, "+6 months"], [12, "+1 year"]].map(([m, t]) => <button key={String(m)} type="button" className="btn secondary small" onClick={() => renew(m as number)}>{t as string}</button>)}
              <button type="button" className="btn secondary small" onClick={() => setUntil("")}>No end date</button>
            </div>
            <label className="field" style={{ margin: 0, maxWidth: 150 }}>Limit ({p.seat_label || "users"})
              <input type="number" name={`seats_${p.code}`} min={1} defaultValue={l?.seats ?? ""} placeholder="Unlimited" />
            </label>
          </div>
          {fl.length > 0 && (
            <div style={{ borderTop: "1px dashed var(--border)", paddingTop: 8 }}>
              <div className="row" style={{ gap: 16, flexWrap: "wrap" }}>
                <b style={{ fontSize: 13 }}>Features</b>
                <label className="check" style={{ fontWeight: 400 }}><input type="radio" name={`scope_${p.code}`} value="all" checked={scope === "all"} onChange={() => setScope("all")} /> All features</label>
                <label className="check" style={{ fontWeight: 400 }}><input type="radio" name={`scope_${p.code}`} value="only" checked={scope === "only"} onChange={() => setScope("only")} /> Only the ticked ones</label>
              </div>
              {scope === "only" && (
                <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill,minmax(230px,1fr))", gap: 4, marginTop: 6 }}>
                  {fl.map((f) => (
                    <label key={f.key} className="check" style={{ fontWeight: 400 }} title={f.detail ?? ""}>
                      <input type="checkbox" name={`ft_${p.code}`} value={f.key} defaultChecked={f.is_core || !!l?.features?.includes(f.key)} disabled={f.is_core} />{f.is_core && <input type="hidden" name={`ft_${p.code}`} value={f.key} />} {f.name}{f.is_core ? " (always on)" : ""}
                    </label>
                  ))}
                </div>
              )}
            </div>
          )}
        </div>
      )}
    </div>
  );
}
