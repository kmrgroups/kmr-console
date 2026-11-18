import { createClient } from "@/lib/supabase/server";

type Kind = { kind: string; at: string; ok: boolean; rows: number; error: string | null; last_ok: string | null; fails_24h: number };
type Dev = { name: string; last_seen: string | null; last_punch: string | null };
type Plant = { unit: string | null; code: string | null; city: string | null; incharge: string | null; phone: string | null; status: string | null; slug: string; name: string; now: string; pc_last_seen: string | null; kinds: Kind[]; devices: Dev[] };
type Tone = "ok" | "warn" | "danger" | "info";

// what each kind of data is called on the plant floor
const LABELS: [string, string][] = [
  ["invoices", "Invoice"], ["production", "Material movement"], ["purchase", "PO · DC · GRN"],
  ["masters", "Masters (party, item)"], ["opsmaster", "Ops master (parts, machines)"], ["calibration", "Calibration"],
];
const DOT: Record<Tone, string> = { ok: "#0f7b4b", warn: "#c98a00", danger: "#b42318", info: "#98a2b3" };

function ago(iso: string | null, now: number): string {
  if (!iso) return "never";
  const m = Math.max(0, Math.round((now - new Date(iso).getTime()) / 60000));
  if (m < 1) return "just now"; if (m < 60) return `${m} min ago`;
  if (m < 1440) return `${Math.floor(m / 60)} h ${m % 60} min ago`;
  return `${Math.floor(m / 1440)} day(s) ago`;
}
const age = (iso: string | null, now: number) => (iso ? (now - new Date(iso).getTime()) / 60000 : Infinity);
const pcTone = (iso: string | null, now: number): Tone => { const m = age(iso, now); return m <= 30 ? "ok" : m <= 180 ? "warn" : "danger"; };
const devTone = (iso: string | null, now: number): Tone => { if (!iso) return "info"; const m = age(iso, now); return m <= 30 ? "ok" : m <= 360 ? "warn" : "danger"; };
const Dot = ({ t }: { t: Tone }) => <span style={{ display: "inline-block", width: 11, height: 11, borderRadius: "50%", background: DOT[t], marginRight: 8, flex: "none" }} />;

/** Dashboard block: is the ERP bridge installed on each plant's PC alive, and is each kind of data (invoice, GRN, DC, calibration, HRM …) arriving? */
export async function BridgeHealth() {
  const supabase = await createClient();
  const { data, error } = await supabase.schema("public").rpc("kmr_bridge_health");
  if (error) return null;           // before migration 0150 the block simply does not show
  const plants = (data ?? []) as Plant[];
  if (!plants.length) return null;
  // Esbee units first
  plants.sort((a, b) => Number(/esbee/i.test(b.name)) - Number(/esbee/i.test(a.name)) || (a.unit || a.name).localeCompare(b.unit || b.name));
  const bad = plants.filter((pl) => pcTone(pl.pc_last_seen, new Date(pl.now).getTime()) === "danger" || pl.kinds.some((k) => !k.ok)).length;

  return (
    <div className="card" style={{ marginTop: 16 }}>
      <h2>ERP bridge — is it working on each unit PC? <span className={`badge ${bad ? "danger" : "ok"}`} style={{ marginLeft: 8 }}>{bad ? `${bad} need attention` : "all working"}</span></h2>
      <p className="muted" style={{ marginTop: 0 }}>Green = working · Amber = late · Red = not reporting or last send failed · Grey = nothing received yet. The bridge sends only what changed, so “last new data” can be old while the PC is still green.</p>
      <div className="grid two">
        {plants.map((pl) => {
          const now = new Date(pl.now).getTime(), pc = pcTone(pl.pc_last_seen, now);
          const kinds = LABELS.map(([k, label]) => ({ label, r: pl.kinds.find((x) => x.kind === k) }));
          return (
            <div key={pl.slug} className="card" style={{ background: "var(--bg, #fff)" }}>
              <div style={{ display: "flex", alignItems: "center", fontWeight: 700, fontSize: 16 }}><Dot t={pc} />{pl.unit || pl.name} <small className="mono muted" style={{ marginLeft: 8 }}>{pl.code}</small>{pl.status && <span className="badge info" style={{ marginLeft: 8 }}>{pl.status}</span>}</div>
              <div className="muted">{[pl.city, pl.incharge && `In-charge: ${pl.incharge}`, pl.phone].filter(Boolean).join(" · ")}</div>
              <div className="muted" style={{ marginBottom: 8 }}>Bridge PC last called in: <b>{ago(pl.pc_last_seen, now)}</b></div>
              <table><tbody>
                {kinds.map(({ label, r }) => {
                  const t: Tone = !r ? "info" : !r.ok ? "danger" : pc;
                  return (
                    <tr key={label}><td style={{ whiteSpace: "nowrap" }}><Dot t={t} />{label}</td>
                      <td className="muted">{!r ? "nothing received yet" : <>last new data {ago(r.at, now)}{r.rows ? ` · ${r.rows} rows` : ""}{!r.ok ? <b style={{ color: "var(--danger)" }}> · FAILED{r.error ? `: ${r.error.slice(0, 90)}` : ""}</b> : r.fails_24h ? <span style={{ color: "var(--warn)" }}> · {r.fails_24h} failed in 24 h</span> : null}</>}</td></tr>
                  );
                })}
                <tr><td style={{ whiteSpace: "nowrap" }}><Dot t={pl.devices.length ? devTone(pl.devices.reduce<string | null>((m, d) => (d.last_seen && (!m || d.last_seen > m) ? d.last_seen : m), null), now) : "info"} />HRM (attendance machines)</td>
                  <td className="muted">{pl.devices.length ? pl.devices.map((d) => `${d.name}: seen ${ago(d.last_seen, now)}${d.last_punch ? `, last punch ${ago(d.last_punch, now)}` : ""}`).join(" · ") : "no machine set up"}</td></tr>
              </tbody></table>
            </div>
          );
        })}
      </div>
    </div>
  );
}
