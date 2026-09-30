import { notFound } from "next/navigation";
import { requireStaff } from "@/lib/auth";
import { createHash } from "crypto";
import { ActionForm } from "@/components/ActionForm";
import { FileField } from "@/components/FileField";
import { canEdit, sectionByKey, type Field } from "@/lib/cms";
import { privateLink, web } from "@/lib/cms-server";
import { p } from "@/lib/base-path";
import { env } from "@/lib/env";
import { deleteRecord, saveRecord } from "@/app/cms-actions";

export const metadata = { title: "Website CMS" };

function Input({ f, v, edit, doc, section }: { f: Field; v: unknown; edit: boolean; doc?: string | null; section: string }) {
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
    case "image": case "document":
      if (ro) return (
        <div className={cls}><span>{f.label}</span>
          {f.type === "image" ? (val ? <img src={val} alt="" className="thumb" style={{ width: 150, height: 110 }} /> : <small className="muted">None</small>)
            : (doc ? <a className="btn secondary small" href={doc} target="_blank" rel="noopener" style={{ alignSelf: "flex-start" }}>Open {f.bucket === "careers" ? "résumé" : "document"}</a> : <small className="muted">None</small>)}
        </div>);
      return <FileField section={section} name={f.k} label={f.label} kind={f.type} value={val} docLink={doc} help={f.help} required={f.required} />;
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
      {s.key === "applications" && !isNew && <div className="card"><div className="row">
        <a className="btn secondary small" href={`mailto:${row.email}?subject=${encodeURIComponent(`Your application: ${row.job_title}`)}`}>Email {String(row.name).split(" ")[0]}</a>
        {Boolean(row.phone) && <a className="btn secondary small" href={`tel:${row.phone}`}>Call</a>}
        {Boolean(row.linkedin_url) && <a className="btn secondary small" href={String(row.linkedin_url)} target="_blank" rel="noopener">LinkedIn</a>}
      </div></div>}
      <div className="card">
        {edit ? (
          <ActionForm key={createHash("md5").update(JSON.stringify(row)).digest("hex")} action={saveRecord} submitLabel={isNew ? `Add ${s.singular}` : "Save changes"} pendingLabel="Saving…" className="formgrid" hidden={{ __section: s.key, __id: isNew ? "" : id }}>
            {s.fields.map((f) => <Input key={f.k} f={f} v={row[f.k]} edit doc={doc} section={s.key} />)}
          </ActionForm>
        ) : <div className="formgrid">{s.fields.map((f) => <Input key={f.k} f={f} v={row[f.k]} edit={false} doc={doc} section={s.key} />)}</div>}
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
