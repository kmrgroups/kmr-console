import { notFound } from "next/navigation";
import { requireStaff } from "@/lib/auth";
import { ActionForm } from "@/components/ActionForm";
import { canEdit, sectionByKey, type Field } from "@/lib/cms";
import { privateLink, web } from "@/lib/cms-server";
import { p } from "@/lib/base-path";
import { env } from "@/lib/env";
import { deleteRecord, saveRecord } from "@/app/cms-actions";

export const metadata = { title: "Website CMS" };

function Input({ f, v, edit, doc }: { f: Field; v: unknown; edit: boolean; doc?: string | null }) {
  const val = v === null || v === undefined ? "" : String(v);
  const wide = f.wide || ["textarea", "longtext", "image", "document"].includes(f.type ?? "");
  const cls = `field${wide ? " full" : ""}`;
  const ro = !edit || f.readonly;
  const help = f.help && <span className="help">{f.help}</span>;
  switch (f.type) {
    case "textarea": case "longtext":
      return <label className={cls}>{f.label}<textarea name={f.k} rows={f.type === "longtext" ? 14 : 4} defaultValue={val} readOnly={ro} required={f.required && !ro} />{help}</label>;
    case "bool": return <label className="field full checkline"><input type="checkbox" name={f.k} defaultChecked={v === true} disabled={ro} /> {f.label}</label>;
    case "select": return ro
      ? <label className={cls}>{f.label}<input readOnly value={f.opts!.find((o) => o[0] === val)?.[1] ?? val} /></label>
      : <label className={cls}>{f.label}<select name={f.k} defaultValue={val} required={f.required}>{!f.required && <option value="" />}{f.opts!.map(([k, l]) => <option key={k} value={k}>{l}</option>)}</select>{help}</label>;
    case "image": case "document": {
      const video = /\.(mp4|webm)(\?|$)/i.test(val);
      return (
        <div className={cls}>
          <span>{f.label}</span>
          <div className="row" style={{ alignItems: "flex-start", gap: 14 }}>
            {f.type === "image"
              ? (val ? (video ? <video src={val} style={{ width: 160, borderRadius: 8 }} controls /> : <img src={val} alt="" style={{ width: 120, height: 120, objectFit: "contain", background: "#f3f4f6", borderRadius: 8, border: "1px solid var(--border)" }} />)
                : <div style={{ width: 120, height: 120, borderRadius: 8, border: "1px dashed var(--border)", display: "grid", placeItems: "center" }}><small className="muted">no image</small></div>)
              : (doc ? <a className="btn secondary small" href={doc} target="_blank" rel="noopener">Open {f.bucket === "careers" ? "résumé" : "document"}</a> : <small className="muted">None</small>)}
            {!ro && <div className="stack" style={{ gap: 6, flex: 1, minWidth: 220 }}>
              <input type="file" name={`${f.k}__file`} accept={f.type === "image" ? "image/*,video/mp4,video/webm" : "application/pdf,image/*"} />
              <input type="hidden" name={f.k} defaultValue={val} />
              {val && <label className="checkline" style={{ display: "flex", gap: 6, fontSize: 13 }}><input type="checkbox" name={`${f.k}__clear`} style={{ width: "auto" }} /> Remove</label>}
              <small className="muted">{f.type === "image" ? "Shown on the public website. JPG, PNG or WebP (MP4 for videos)." : "Stored privately — opened with a link that expires."}</small>
              {help}
            </div>}
          </div>
        </div>);
    }
    case "date": return <label className={cls}>{f.label}<input name={f.k} type="date" defaultValue={val.slice(0, 10)} readOnly={ro} required={f.required && !ro} />{help}</label>;
    default: return <label className={cls}>{f.label}<input name={f.k} type={f.type === "email" ? "email" : "text"} inputMode={f.type === "number" || f.type === "money" ? "decimal" : undefined}
      defaultValue={val} readOnly={ro} required={f.required && !ro} />{help}</label>;
  }
}

export default async function SectionEdit({ params }: { params: Promise<{ section: string; id: string }> }) {
  const { section, id } = await params;
  const s = sectionByKey(section); if (!s) notFound();
  const staff = await requireStaff();
  const edit = canEdit(s, staff.role);
  const isNew = id === "new";
  if (isNew && (s.noCreate || !edit)) notFound();
  let row: Record<string, unknown> = { ...(s.defaults ?? {}), ...(s.scope ?? {}) };
  if (!isNew) {
    const { data } = await web().from(s.table).select("*").eq("id", id).maybeSingle();
    if (!data) notFound();
    row = data;
  }
  const docField = s.fields.find((f) => f.type === "document");
  const doc = docField ? await privateLink(row[docField.k] as string, docField.bucket) : null;
  const title = isNew ? `New ${s.singular}` : s.single ? s.label : String((s.titleOf ?? ["name", "title", "headline", "value"]).map((k) => row[k]).find(Boolean) ?? s.label);
  const preview = !isNew && s.preview?.(row);
  const shown = s.visible ? Boolean(row[s.visible]) : true;

  return (
    <>
      <div className="pagehead">
        <div>{!s.single && <p style={{ margin: 0 }}><a href={p(`/cms/${s.key}`)} className="muted">← {s.label}</a></p>}
          <h1>{title}</h1><p>{s.single ? s.intro : s.visible && !isNew ? (shown ? "Shown on the website." : "Hidden — not shown on the website.") : ""}</p></div>
        {preview && shown && <a className="btn secondary" href={env.platformUrl + preview} target="_blank" rel="noopener">View on the website ↗</a>}
      </div>
      {!edit && <div className="alert warn">Your role can view this but not change it.</div>}
      {Boolean(row.ops_code) && <div className="alert info" style={{ marginBottom: 12 }}>Imported from the Operations Master (part {String(row.ops_code)}). Importing again refreshes the name and description only.</div>}
      {s.key === "applications" && !isNew && <div className="card"><div className="row">
        <a className="btn secondary small" href={`mailto:${row.email}?subject=${encodeURIComponent(`Your application: ${row.job_title}`)}`}>Email {String(row.name).split(" ")[0]}</a>
        {Boolean(row.phone) && <a className="btn secondary small" href={`tel:${row.phone}`}>Call</a>}
        {Boolean(row.linkedin_url) && <a className="btn secondary small" href={String(row.linkedin_url)} target="_blank" rel="noopener">LinkedIn</a>}
      </div></div>}
      <div className="card">
        {edit ? (
          <ActionForm action={saveRecord} submitLabel={isNew ? `Add ${s.singular}` : "Save changes"} pendingLabel="Saving…" className="formgrid" hidden={{ __section: s.key, __id: isNew ? "" : id }}>
            {s.fields.map((f) => <Input key={f.k} f={f} v={row[f.k]} edit doc={doc} />)}
          </ActionForm>
        ) : <div className="formgrid">{s.fields.map((f) => <Input key={f.k} f={f} v={row[f.k]} edit={false} doc={doc} />)}</div>}
      </div>
      {edit && !isNew && !s.noDelete && (
        <div className="card">
          <h2>Delete</h2>
          <p className="muted" style={{ marginTop: -4 }}>{s.visible ? "Deleting cannot be undone. To take it off the website but keep it, untick “Show” instead." : "Deleting cannot be undone."}</p>
          <ActionForm action={deleteRecord} submitLabel={`Delete ${s.singular}`} variant="danger" hidden={{ __section: s.key, __id: id }} confirm={`Delete this ${s.singular}? This cannot be undone.`} />
        </div>
      )}
    </>
  );
}
