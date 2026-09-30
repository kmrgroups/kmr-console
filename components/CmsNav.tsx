"use client";
import { usePathname } from "next/navigation";
import { p } from "@/lib/base-path";

export type CmsLink = { href: string; label: string; count?: number | null };
export type CmsGroup = { label: string; links: CmsLink[] };

/** The Website CMS's own menu: sections grouped the way the website is organised. */
export function CmsNav({ groups, site }: { groups: CmsGroup[]; site: string }) {
  const path = usePathname();
  const on = (href: string) => href === "/cms" ? path === "/cms" : path === href || path.startsWith(href + "/");
  return (
    <aside className="cmsnav">
      <a href={p("/cms")} className={`cmsnav-home${on("/cms") ? " active" : ""}`}>Overview</a>
      {groups.map((g) => (
        <div key={g.label} className="cmsnav-group">
          <p>{g.label}</p>
          {g.links.map((l) => (
            <a key={l.href} href={p(l.href)} className={on(l.href) ? "active" : ""}>
              <span>{l.label}</span>{l.count ? <b>{l.count}</b> : null}
            </a>
          ))}
        </div>
      ))}
      <a href={site} target="_blank" rel="noopener" className="cmsnav-site">Open the website ↗</a>
    </aside>
  );
}
