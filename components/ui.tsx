

export function Avatar({ name, src, size }: { name: string; src?: string | null; size?: "lg" }) {
  const initials = name.split(/\s+/).filter(Boolean).slice(0, 2).map((w) => w[0]!.toUpperCase()).join("");
  return src ? (
    <img className={`avatar${size ? " " + size : ""}`} src={src} alt="" />
  ) : (
    <span className={`avatar${size ? " " + size : ""}`}>{initials}</span>
  );
}

export function fullName(e: { first_name: string; last_name?: string | null }) {
  return [e.first_name, e.last_name].filter(Boolean).join(" ");
}

export function fmtDate(d: string | null | undefined) {
  if (!d) return "—";
  const dt = new Date(d.length === 10 ? d + "T00:00:00" : d);
  return dt.toLocaleDateString("en-IN", { day: "2-digit", month: "short", year: "numeric" });
}

export function fmtDateTime(d: string | null | undefined) {
  if (!d) return "—";
  return new Date(d).toLocaleString("en-IN", { day: "2-digit", month: "short", hour: "2-digit", minute: "2-digit", timeZone: "Asia/Kolkata" });
}

/** Supabase returns joined rows as object or array depending on the relation; normalise to one object */
export function one<T>(x: T | T[] | null | undefined): T | null {
  return Array.isArray(x) ? x[0] ?? null : x ?? null;
}

export function Empty({ children }: { children: React.ReactNode }) {
  return <div className="empty">{children}</div>;
}
