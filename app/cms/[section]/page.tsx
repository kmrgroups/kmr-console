import { notFound, redirect } from "next/navigation";
import { requireStaff } from "@/lib/auth";
import { ActionForm } from "@/components/ActionForm";
import { Empty, fmtDate } from "@/components/ui";
import { BUSINESS_LABEL, canEdit, sectionByKey, type Section } from "@/lib/cms";
import { web } from "@/lib/cms-server";
import { p } from "@/lib/base-path";
import { env } from "@/lib/env";
import { deleteRecord, toggleVisible } from "@/app/cms-actions";

export const metadata = { title: "Website CMS" };

function cell(s: Section, k: string, v: unknown) {
  const f = s.fields.find((x) => x.k === k);
  if (k === s.visible) return v ? <span className="badge ok">shown</span> : <span className="badge">hidden</span>;
  if (v === null || v === undefined || v === "") return <small className="muted">—</small>;
  if (f?.type === "image") return /\.(mp4|webm)(\?|$)/i.test(String(v)) ? <span className="badge">video</span> : <img className="thumb" src={String(v)} alt="" />;
  if (f?.type === "bool") return v ? "yes" : <small className="muted">no</small>;
  if (f?.type === "money") return <span style={{ whiteSpace: "nowrap" }}>{Number(v) > 0 ? `₹${Number(v).toLocaleString("en-IN")}` : <small className="muted">on request</small>}</span>;
  if (f?.type === "date" || k.endsWith("_at")) return <span style={{ whiteSpace: "nowrap" }}>{fmtDate(String(v))}</span>;
  if (k === "status") return <span className={`badge${v === "new" ? " warn" : v === "hired" || v === "offered" ? " ok" : ""}`}>{String(v)}</span>;
  if (f?.type === "select") return f.opts?.find((o) => o[0] === v)?.[1] ?? String(v);
  if (k === "business") return BUSINESS_LABEL[String(v)] ?? String(v);
  const t = String(v); return t.length > 70 ? t.slice(0, 70) + "…" : t;
}

export default async function SectionList({ params, searchParams }: { params: Promise<{ section: string }>; searchParams: Promise<Record<string, string | undefined>> }) {
  const { section } = await params; const sp = await searchParams;
  const s = sectionByKey(section); if (!s) notFound();
  const staff = await requireStaff();
  const edit = canEdit(s, staff.role);
  let q = web().from(s.table).select("*").order(s.order[0], { ascending: s.order[1], nullsFirst: false }).limit(500);
  for (const [k, v] of Object.entries(s.scope ?? {})) q = q.eq(k, v);
  if (s.filter?.restrict) q = q.in(s.filter.k, s.filter.opts.map((o) => o[0]));
  if (s.filter && sp.f) q = q.eq(s.filter.k, sp.f);
  if (s.visible && sp.v) q = q.eq(s.visible, sp.v === "shown");
  if (s.search && sp.q) q = q.or(s.search.map((c) => `${c}.ilike.%${sp.q!.replace(/[%,()]/g, " ")}%`).join(","));
  const { data: rows, error } = await q;
  if (s.single && !error) redirect(`/cms/${s.key}/${rows?.[0]?.id ?? "new"}`);
  const head = (k: string) => k === s.visible ? "On website" : s.fields.find((f) => f.k === k)?.label.replace(/ \(.*\)$/, "") ?? (k === "created_at" ? "Received" : k === "updated_at" ? "Updated" : k);

  return (
    <>
      <div className="pagehead">
        <div><h1>{s.label}</h1><p>{s.intro}</p></div>
        <div className="row">
          {edit && !s.noCreate && <a className="btn" href={p(`/cms/${s.key}/new`)}>+ Add {s.singular}</a>}
        </div>
      </div>
      {error && <div className="alert error">{/relation .* does not exist|column/i.test(error.message) ? "The website database is not up to date for this section. Run the website's supabase/add-premium-site.sql, then refresh." : error.message}</div>}
      {(s.search || s.filter || s.visible) && (
        <form className="toolbar">
          {s.search && <input name="q" defaultValue={sp.q ?? ""} placeholder="Search…" />}
          {s.filter && <select name="f" defaultValue={sp.f ?? ""}><option value="">All — {s.filter.label.toLowerCase()}</option>{s.filter.opts.map(([v, l]) => <option key={v} value={v}>{l}</option>)}</select>}
          {s.visible && <select name="v" defaultValue={sp.v ?? ""}><option value="">Shown and hidden</option><option value="shown">Shown only</option><option value="hidden">Hidden only</option></select>}
          <button className="btn secondary">Show</button>
        </form>
      )}
      <div className="card" style={{ padding: 0 }}>
        {rows?.length ? (
          <div className="tablewrap" style={{ border: 0 }}><table>
            <thead><tr>{s.list.map((k) => <th key={k}>{head(k)}</th>)}<th /></tr></thead>
            <tbody>{rows.map((row) => {
              const shown = s.visible ? Boolean(row[s.visible]) : true;
              const preview = s.preview?.(row);
              return (
                <tr key={row.id} className={shown ? "" : "hidden-row"}>
                  {s.list.map((k, i) => <td key={k}>{cell(s, k, row[k])}{i === 1 && row.sample ? <> <span className="badge warn">sample</span></> : null}</td>)}
                  <td><div className="rowactions">
                    {preview && shown && <a className="btn secondary small" href={env.platformUrl + preview} target="_blank" rel="noopener" title="View on the website">View</a>}
                    <a className="btn secondary small" href={p(`/cms/${s.key}/${row.id}`)}>{edit ? "Edit" : "Open"}</a>
                    {edit && s.visible && <ActionForm action={toggleVisible} submitLabel={shown ? "Hide" : "Show"} variant="secondary" hidden={{ __section: s.key, __id: row.id, show: shown ? "0" : "1" }} />}
                    {edit && !s.noDelete && <ActionForm action={deleteRecord} submitLabel="Delete" variant="danger" hidden={{ __section: s.key, __id: row.id, __back: "list" }} confirm={`Delete this ${s.singular}? This cannot be undone.`} />}
                  </div></td>
                </tr>);
            })}</tbody></table></div>
        ) : !error && <Empty>{sp.q || sp.f || sp.v ? "Nothing matches." : `Nothing here yet.${edit && !s.noCreate ? ` Add the first ${s.singular}.` : ""}`}</Empty>}
      </div>
    </>
  );
}
