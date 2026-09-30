import { notFound, redirect } from "next/navigation";
import { requireStaff } from "@/lib/auth";
import { AppShell } from "@/components/AppShell";
import { Empty, fmtDate } from "@/components/ui";
import { BUSINESS_LABEL, resourceByKey, type Resource } from "@/lib/manage";
import { canEdit, web } from "@/lib/manage-server";
import { p } from "@/lib/base-path";

export const metadata = { title: "Manage" };

function cell(r: Resource, k: string, v: unknown) {
  const f = r.fields.find((x) => x.k === k);
  if (v === null || v === undefined || v === "") return <small className="muted">—</small>;
  if (f?.type === "image") return <img src={String(v)} alt="" style={{ width: 44, height: 44, objectFit: "cover", borderRadius: 6, border: "1px solid var(--border)" }} />;
  if (f?.type === "bool") return v ? <span className="badge ok">yes</span> : <span className="badge">no</span>;
  if (f?.type === "money") return <span style={{ whiteSpace: "nowrap" }}>₹{Number(v).toLocaleString("en-IN")}</span>;
  if (f?.type === "date" || k.endsWith("_at")) return fmtDate(String(v));
  if (f?.type === "select") return f.opts?.find((o) => o[0] === v)?.[1] ?? String(v);
  if (k === "business") return BUSINESS_LABEL[String(v)] ?? String(v);
  const s = String(v); return s.length > 70 ? s.slice(0, 70) + "…" : s;
}

export default async function ManageList({ params, searchParams }: { params: Promise<{ resource: string }>; searchParams: Promise<Record<string, string | undefined>> }) {
  const { resource } = await params; const sp = await searchParams;
  const r = resourceByKey(resource); if (!r) notFound();
  const staff = await requireStaff();
  const edit = canEdit(r, staff);
  let q = web().from(r.table).select("*").order(r.order[0], { ascending: r.order[1], nullsFirst: false }).limit(500);
  if (r.filter && sp.f) q = q.eq(r.filter.k, sp.f);
  if (r.search && sp.q) q = q.or(r.search.map((c) => `${c}.ilike.%${sp.q!.replace(/[%,()]/g, " ")}%`).join(","));
  const { data: rows, error } = await q;
  if (r.single && !error) redirect(`/manage/${r.key}/${rows?.[0]?.id ?? "new"}`);
  const head = (k: string) => r.fields.find((f) => f.k === k)?.label ?? (k === "updated_at" ? "Updated" : k);

  return (
    <AppShell staff={staff} active={`/${r.section}`}>
      <div className="pagehead">
        <div><p style={{ margin: 0 }}><a href={p(`/${r.section}`)} className="muted">← {r.section === "website" ? "Website" : "Operations"}</a></p><h1>{r.label}</h1><p>{r.intro}</p></div>
        <div className="row">
          {r.key === "products" && edit && <a className="btn secondary" href={p("/website/publish")}>Publish from Operations Master</a>}
          {edit && !r.noCreate && <a className="btn" href={p(`/manage/${r.key}/new`)}>+ Add {r.singular}</a>}
        </div>
      </div>
      {error && <div className="alert error">{/relation .* does not exist|column/i.test(error.message) ? "The website tables are not set up for this yet. Run the website's supabase SQL files (see the setup guide), then refresh." : error.message}</div>}
      {(r.search || r.filter) && (
        <form className="row" style={{ marginBottom: 12 }}>
          {r.search && <input name="q" defaultValue={sp.q ?? ""} placeholder="Search…" style={{ maxWidth: 280 }} />}
          {r.filter && <select name="f" defaultValue={sp.f ?? ""} style={{ maxWidth: 220 }}><option value="">All — {r.filter.label.toLowerCase()}</option>{r.filter.opts.map(([v, l]) => <option key={v} value={v}>{l}</option>)}</select>}
          <button className="btn secondary">Show</button>
        </form>
      )}
      <div className="card" style={{ padding: 0 }}>
        {rows?.length ? (
          <div className="tablewrap" style={{ border: 0 }}><table>
            <thead><tr>{r.list.map((k) => <th key={k}>{head(k)}</th>)}<th /></tr></thead>
            <tbody>{rows.map((row) => (
              <tr key={row.id}>{r.list.map((k) => <td key={k}>{cell(r, k, row[k])}</td>)}
                <td style={{ textAlign: "right" }}><a className="btn secondary small" href={p(`/manage/${r.key}/${row.id}`)}>{edit ? "Edit" : "View"}</a></td></tr>))}
            </tbody></table></div>
        ) : !error && <Empty>{sp.q || sp.f ? "Nothing matches." : `No ${r.label.toLowerCase()} yet.`}</Empty>}
      </div>
    </AppShell>
  );
}
