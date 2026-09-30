import { notFound } from "next/navigation";
import { requireStaff } from "@/lib/auth";
import { AppShell } from "@/components/AppShell";
import { ActionForm } from "@/components/ActionForm";
import { resourceByKey, type Field } from "@/lib/manage";
import { canEdit, documentLink, web } from "@/lib/manage-server";
import { p } from "@/lib/base-path";
import { env } from "@/lib/env";
import { deleteRecord, saveRecord } from "@/app/manage-actions";

export const metadata = { title: "Edit" };

function Input({ f, v, edit, docUrl }: { f: Field; v: unknown; edit: boolean; docUrl?: string | null }) {
  const val = v === null || v === undefined ? "" : String(v);
  const cls = `field${f.wide || f.type === "textarea" || f.type === "image" || f.type === "document" ? " full" : ""}`;
  const ro = !edit;
  switch (f.type) {
    case "textarea": return <label className={cls}>{f.label}<textarea name={f.k} rows={f.k === "content" ? 16 : 4} defaultValue={val} readOnly={ro} required={f.required} />{f.help && <span className="help">{f.help}</span>}</label>;
    case "bool": return <label className="field full checkline"><input type="checkbox" name={f.k} defaultChecked={v === true} disabled={ro} /> {f.label}</label>;
    case "select": return <label className={cls}>{f.label}<select name={f.k} defaultValue={val} disabled={ro} required={f.required}>{!f.required && <option value="" />}{f.opts!.map(([k, l]) => <option key={k} value={k}>{l}</option>)}</select>{f.help && <span className="help">{f.help}</span>}</label>;
    case "image": case "document": return (
      <div className={cls}>
        <span>{f.label}</span>
        <div className="row" style={{ alignItems: "flex-start", gap: 14 }}>
          {f.type === "image" ? (val ? <img src={val} alt="" style={{ width: 96, height: 96, objectFit: "cover", borderRadius: 8, border: "1px solid var(--border)" }} /> : <div style={{ width: 96, height: 96, borderRadius: 8, border: "1px dashed var(--border)", display: "grid", placeItems: "center" }}><small className="muted">none</small></div>)
            : (docUrl ? <a className="btn secondary small" href={docUrl} target="_blank" rel="noopener">Open current document</a> : <small className="muted">No document</small>)}
          {edit && <div className="stack" style={{ gap: 6, flex: 1, minWidth: 220 }}>
            <input type="file" name={`${f.k}__file`} accept={f.type === "image" ? "image/*,video/mp4,video/webm" : "application/pdf,image/*"} />
            <input type="hidden" name={f.k} defaultValue={val} />
            {val && <label className="checkline" style={{ display: "flex", gap: 6, fontSize: 13 }}><input type="checkbox" name={`${f.k}__clear`} style={{ width: "auto" }} /> Remove</label>}
            <small className="muted">{f.type === "image" ? "Shown on the public website." : "Stored privately — opened with a link that expires."}</small>
          </div>}
        </div>
      </div>);
    default: return <label className={cls}>{f.label}<input name={f.k} type={f.type === "number" || f.type === "money" ? "text" : f.type === "date" ? "date" : "text"} inputMode={f.type === "number" || f.type === "money" ? "decimal" : undefined}
      defaultValue={f.type === "date" ? val.slice(0, 10) : val} readOnly={ro} required={f.required} />{f.help && <span className="help">{f.help}</span>}</label>;
  }
}

export default async function ManageEdit({ params }: { params: Promise<{ resource: string; id: string }> }) {
  const { resource, id } = await params;
  const r = resourceByKey(resource); if (!r) notFound();
  const staff = await requireStaff();
  const edit = canEdit(r, staff);
  const isNew = id === "new";
  if (isNew && r.noCreate) notFound();
  let row: Record<string, unknown> = { ...(r.defaults ?? {}) };
  if (!isNew) {
    const { data } = await web().from(r.table).select("*").eq("id", id).maybeSingle();
    if (!data) notFound();
    row = data;
  }
  const docField = r.fields.find((f) => f.type === "document");
  const docUrl = docField ? await documentLink(row[docField.k] as string) : null;
  const title = isNew ? `New ${r.singular}` : String(row.name ?? row.title ?? row.full_name ?? row.headline ?? row.trade_name ?? r.label);

  return (
    <AppShell staff={staff} active={`/${r.section}`}>
      <div className="pagehead">
        <div><p style={{ margin: 0 }}><a href={p(r.single ? `/${r.section}` : `/manage/${r.key}`)} className="muted">← {r.single ? (r.section === "website" ? "Website" : "Operations") : r.label}</a></p>
          <h1>{title}</h1>{r.single && <p>{r.intro}</p>}</div>
        {r.key === "products" && !isNew && Boolean(row.is_active) && <a className="btn secondary" href={`${env.platformUrl}/products/${id}`} target="_blank" rel="noopener">View on website</a>}
      </div>
      {!edit && <div className="alert warn">Your role can view this but not change it.</div>}
      {r.key === "products" && Boolean(row.ops_code) && <div className="alert info" style={{ marginBottom: 12 }}>Published from the Operations Master (part {String(row.ops_code)}). Publishing again refreshes the name and description; price, stock, photo and visibility stay as you set them here.</div>}
      <div className="card">
        {edit ? (
          <ActionForm action={saveRecord} submitLabel={isNew ? `Add ${r.singular}` : "Save"} pendingLabel="Saving…" className="formgrid" hidden={{ __resource: r.key, __id: isNew ? "" : id }}>
            {r.fields.map((f) => <Input key={f.k} f={f} v={row[f.k]} edit docUrl={docUrl} />)}
          </ActionForm>
        ) : <div className="formgrid">{r.fields.map((f) => <Input key={f.k} f={f} v={row[f.k]} edit={false} docUrl={docUrl} />)}</div>}
      </div>
      {edit && !isNew && !r.noDelete && (
        <div className="card">
          <h2>Delete</h2>
          <p className="muted" style={{ marginTop: -4 }}>Deleting cannot be undone. To keep the history, untick “Active” / “Show on the website” instead.</p>
          <ActionForm action={deleteRecord} submitLabel={`Delete ${r.singular}`} variant="danger" hidden={{ __resource: r.key, __id: id }} confirm={`Delete this ${r.singular}?`} />
        </div>
      )}
    </AppShell>
  );
}
