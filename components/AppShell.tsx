import { ROLE_LABELS, type Staff } from "@/lib/auth";
import { signOut } from "@/app/login/actions";
import { Icon, type IconName } from "./Icon";
import { Flash } from "./Flash";
import { readFlash } from "@/lib/flash";
import { p } from "@/lib/base-path";

const NAV: { href: string; label: string; icon: IconName; owner?: boolean }[] = [
  { href: "/", label: "Dashboard", icon: "home" },
  { href: "/customers", label: "Customers", icon: "building" },
  { href: "/tickets", label: "Support tickets", icon: "inbox" },
  { href: "/leads", label: "Pilot requests", icon: "mail" },
  { href: "/products", label: "Products & versions", icon: "layers" },
  { href: "/staff", label: "KMR staff", icon: "shield" },
  { href: "/data", label: "Data & backups", icon: "download" },
];

export async function AppShell({ staff, active, children }: { staff: Staff; active: string; children: React.ReactNode }) {
  return (
    <div className="shell">
      <input type="checkbox" id="navtoggle" aria-hidden="true" />
      <div className="topbar"><span className="t">KMR Console</span><label htmlFor="navtoggle" aria-label="Menu">☰</label></div>
      <aside className="sidebar">
        <div className="brand"><div className="kmr-minimark">K<b>M</b>R <small>CONSOLE</small></div></div>
        <nav>
          {NAV.map((i) => (
            <a key={i.href} href={p(i.href)} className={`nav${active === i.href ? " active" : ""}`}><Icon name={i.icon} /> {i.label}</a>
          ))}
        </nav>
        <div className="who">
          <div style={{ fontWeight: 600 }}>{staff.full_name}</div>
          <div style={{ opacity: 0.75, marginBottom: 6 }}>{ROLE_LABELS[staff.role]}</div>
          <form action={signOut}><button>Sign out</button></form>
        </div>
      </aside>
      <main className="main"><Flash msg={await readFlash()} />{children}</main>
    </div>
  );
}
