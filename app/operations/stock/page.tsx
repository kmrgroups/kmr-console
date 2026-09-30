import { requireStaff } from "@/lib/auth";
import { AppShell } from "@/components/AppShell";
import { ActionForm } from "@/components/ActionForm";
import { Empty, fmtDate } from "@/components/ui";
import { web } from "@/lib/manage-server";
import { p } from "@/lib/base-path";
import { addStockMove } from "@/app/website-actions";

export const metadata = { title: "Stock" };
const TYPES: [string, string][] = [["purchase_receipt", "Purchase receipt (+)"], ["production_output", "Production output (+)"], ["opening", "Opening stock (+)"],
  ["sales_dispatch", "Sales dispatch (−)"], ["production_consumption", "Production consumption (−)"], ["adjustment", "Adjustment (± as entered)"]];

export default async function Stock() {
  const staff = await requireStaff();
  const db = web();
  const [{ data: items }, { data: whs }, { data: bal }, { data: moves }] = await Promise.all([
    db.from("inventory_items").select("id,item_code,name,unit_of_measure,reorder_level").eq("is_active", true).order("item_code"),
    db.from("warehouses").select("id,name").eq("is_active", true).order("name"),
    db.from("stock_balances").select("*"),
    db.from("stock_transactions").select("*").order("created_at", { ascending: false }).limit(50),
  ]);
  const item = Object.fromEntries((items ?? []).map((x) => [x.id, x])); const wh = Object.fromEntries((whs ?? []).map((x) => [x.id, x.name]));
  const today = new Date().toISOString().slice(0, 10);
  return (
    <AppShell staff={staff} active="/operations">
      <div className="pagehead"><div><p style={{ margin: 0 }}><a href={p("/operations")} className="muted">← Operations</a></p><h1>Stock</h1><p>Stock on hand = the sum of all movements per item and warehouse.</p></div></div>
      <div className="grid two">
        <div className="card">
          <h2>On hand</h2>
          {bal?.length ? <div className="tablewrap"><table><thead><tr><th>Item</th><th>Warehouse</th><th style={{ textAlign: "right" }}>Qty</th></tr></thead>
            <tbody>{bal.map((b, i) => { const it = item[b.item_id]; const low = it && Number(b.quantity_on_hand) <= Number(it.reorder_level ?? 0);
              return <tr key={i}><td><b className="mono">{it?.item_code ?? "?"}</b> {it?.name}</td><td>{wh[b.warehouse_id] ?? "—"}</td>
                <td style={{ textAlign: "right" }}>{Number(b.quantity_on_hand).toLocaleString("en-IN")} {it?.unit_of_measure}{low && <span className="badge warn" style={{ marginLeft: 6 }}>reorder</span>}</td></tr>; })}</tbody></table></div>
            : <Empty>No stock recorded yet.</Empty>}
        </div>
        <div className="card">
          <h2>Record a movement</h2>
          {!items?.length || !whs?.length ? <p className="muted">Add <a href={p("/manage/items")}>inventory items</a> and a <a href={p("/manage/warehouses")}>warehouse</a> first.</p> : (
            <ActionForm action={addStockMove} submitLabel="Record" className="formgrid" resetOnSuccess>
              <label className="field">Item<select name="item_id" required>{items.map((x) => <option key={x.id} value={x.id}>{x.item_code} — {x.name}</option>)}</select></label>
              <label className="field">Warehouse<select name="warehouse_id" required>{whs.map((x) => <option key={x.id} value={x.id}>{x.name}</option>)}</select></label>
              <label className="field">Movement<select name="transaction_type" defaultValue="purchase_receipt">{TYPES.map(([k, l]) => <option key={k} value={k}>{l}</option>)}</select></label>
              <label className="field">Quantity<input name="quantity" inputMode="decimal" required /></label>
              <label className="field">Unit cost (₹)<input name="unit_cost" inputMode="decimal" /></label>
              <label className="field">Date<input type="date" name="transaction_date" defaultValue={today} max={today} /></label>
              <label className="field full">Reference (GRN, invoice, note)<input name="reference_note" /></label>
            </ActionForm>)}
        </div>
      </div>
      <div className="card">
        <h2>Recent movements</h2>
        {moves?.length ? <div className="tablewrap"><table><thead><tr><th>Date</th><th>Item</th><th>Warehouse</th><th>Movement</th><th style={{ textAlign: "right" }}>Qty</th><th>Reference</th></tr></thead>
          <tbody>{moves.map((m) => <tr key={m.id}><td>{fmtDate(m.transaction_date)}</td><td>{item[m.item_id]?.item_code ?? "?"}</td><td>{wh[m.warehouse_id] ?? "—"}</td>
            <td>{TYPES.find((t) => t[0] === m.transaction_type)?.[1].replace(/ \(.*\)/, "") ?? m.transaction_type}</td>
            <td style={{ textAlign: "right", color: Number(m.quantity) < 0 ? "var(--danger)" : "var(--ok)" }}>{Number(m.quantity) > 0 ? "+" : ""}{Number(m.quantity)}</td><td><small>{m.reference_note}</small></td></tr>)}</tbody></table></div>
          : <Empty>None yet.</Empty>}
      </div>
    </AppShell>
  );
}
