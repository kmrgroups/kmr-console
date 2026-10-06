"use client";
import { useState } from "react";
import { appPrice, featurePrice, type Feature } from "@/lib/features";
import { inr } from "@/lib/quote";

export type InvProduct = { code: string; name: string; seat_label: string; seats: number; on: boolean; minSeats: number; flat: { month: number | null; year: number | null }; features: Feature[] };

/** Invoice form rows: tick an app, tick its features, and the price per user is the sum — the same flow as the quotation. */
export function InvoiceProducts({ products, currency, defaultFrom }: { products: InvProduct[]; currency: string; defaultFrom: string }) {
  const [period, setPeriod] = useState<"month" | "year">("year");
  const [on, setOn] = useState<Record<string, boolean>>(() => Object.fromEntries(products.map((x) => [x.code, x.on])));
  const [seats, setSeats] = useState<Record<string, number>>(() => Object.fromEntries(products.map((x) => [x.code, x.seats])));
  const [chosen, setChosen] = useState<Record<string, Set<string>>>(() => Object.fromEntries(products.map((x) => [x.code, new Set(x.features.map((f) => f.id))])));
  const byFeature = currency === "INR";       // feature prices are in INR; other currencies use the whole-app price
  let total = 0;
  return (
    <>
      <div className="row">
        <label className="field" style={{ flex: 1, minWidth: 160 }}>Billing<select name="period" value={period} onChange={(e) => setPeriod(e.target.value as "month" | "year")}><option value="year">Yearly</option><option value="month">Monthly</option></select></label>
        <label className="field" style={{ flex: 1, minWidth: 160 }}>Period starts<input type="date" name="from" defaultValue={defaultFrom} required /></label>
      </div>
      <div className="stack" style={{ gap: 6 }}>
        {products.map((pr) => {
          const useFeat = byFeature && pr.features.length > 0, ch = chosen[pr.code] ?? new Set<string>();
          const each = useFeat ? appPrice(pr.features, ch, period) : pr.flat[period] ?? 0;
          const setup = useFeat ? pr.features.filter((f) => f.is_core || ch.has(f.id)).reduce((a, f) => a + (Number(f.setup_fee) || 0), 0) : 0;
          const qty = Math.max(seats[pr.code] || 0, pr.minSeats), amount = each * qty + setup;
          if (on[pr.code]) total += amount;
          return (
            <div key={pr.code} style={{ border: "1px solid var(--border)", borderRadius: 8, padding: "8px 12px" }}>
              <div className="row" style={{ justifyContent: "space-between" }}>
                <label style={{ display: "flex", gap: 8, alignItems: "center", flex: 1, minWidth: 200 }}>
                  <input type="checkbox" name="product" value={pr.code} checked={!!on[pr.code]} onChange={(e) => setOn({ ...on, [pr.code]: e.target.checked })} />
                  <span><b>{pr.name}</b><br /><small className="muted">{each ? `${inr(each)} per ${pr.seat_label.replace(/s$/, "")} / ${period}` : `no ${period === "year" ? "yearly" : "monthly"} price`}{pr.minSeats > 1 ? `, min ${pr.minSeats}` : ""}</small></span>
                </label>
                <label className="row" style={{ gap: 6, fontSize: 13 }}>{pr.seat_label}<input type="number" name={`seats_${pr.code}`} min={1} value={seats[pr.code]} onChange={(e) => setSeats({ ...seats, [pr.code]: Number(e.target.value) })} style={{ width: 90 }} /></label>
                <b style={{ minWidth: 90, textAlign: "right" }}>{on[pr.code] ? inr(amount) : "—"}</b>
              </div>
              {on[pr.code] && useFeat && (
                <div style={{ display: "grid", gap: 4, margin: "8px 0 2px 26px" }}>
                  {pr.features.map((f) => (
                    <label key={f.id} style={{ display: "flex", gap: 8, fontSize: 13, alignItems: "center" }}>
                      <input type="checkbox" name={`feat_${pr.code}`} value={f.id} checked={f.is_core || ch.has(f.id)} disabled={f.is_core}
                        onChange={(e) => { const c = new Set(ch); if (e.target.checked) c.add(f.id); else c.delete(f.id); setChosen({ ...chosen, [pr.code]: c }); }} />
                      {f.is_core && <input type="hidden" name={`feat_${pr.code}`} value={f.id} />}
                      <span style={{ flex: 1 }}>{f.name}{f.is_core && <small className="muted"> · core</small>}</span>
                      <span className="muted">{inr(featurePrice(f, period))}</span>
                    </label>))}
                </div>)}
              {on[pr.code] && !useFeat && pr.features.length > 0 && <small className="muted" style={{ display: "block", marginLeft: 26 }}>Feature prices are in ₹; this customer is billed in {currency}, so the whole-app price is used.</small>}
            </div>);
        })}
      </div>
      <p className="muted" style={{ margin: "8px 0 0", fontSize: 13 }}>Subtotal before GST: <b>{inr(total)}</b> — the invoice shows one line per feature.</p>
    </>
  );
}
