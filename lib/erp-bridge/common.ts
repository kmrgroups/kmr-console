/** Helpers shared by the ERP bridge converters. A table arrives as { c: [column names], r: [[values as text]] }. */
export type Table = { c: string[]; r: (string | null)[][] };
export type Row = Record<string, string>;
export type Tables = Record<string, Table | undefined>;

export function rows(t: Table | undefined): Row[] {
  if (!t || !Array.isArray(t.c) || !Array.isArray(t.r)) return [];
  const c = t.c;
  return t.r.map((r) => { const o: Row = {}; for (let i = 0; i < c.length; i++) o[c[i]] = r[i] == null ? "" : String(r[i]); return o; });
}
/** Python-style number: text with commas allowed, anything else is 0 */
export function num(x: unknown): number { const s = String(x ?? "").replace(/,/g, ""); if (s.trim() === "") return 0; const n = Number(s); return Number.isFinite(n) ? n : 0; }
/** float() that gives null when the text is not a number */
export function F(x: unknown): number | null { const s = String(x ?? "").trim(); if (s === "") return null; const n = Number(s); return Number.isFinite(n) ? n : null; }
export const trim = (x: unknown) => String(x ?? "").trim();
export const low = (x: unknown) => trim(x).toLowerCase();
export const cl = (x: unknown) => String(x ?? "").replace(/\s+/g, " ").trim();
export const nz = (x: unknown) => String(x ?? "").toLowerCase().replace(/[^a-z0-9]/g, "");
/** Python round(x, n): the exact value of the number decides; an exact half goes to the even digit */
export function pyRoundN(x: number, n: number): number {
  if (!Number.isFinite(x)) return x;
  const ex = Math.abs(x).toFixed(Math.min(100, n + 60)), dot = ex.indexOf("."), tail = ex.slice(dot + 1 + n);
  if (/^50*$/.test(tail)) {                      // an exact half: the even last digit wins
    let head = BigInt(ex.slice(0, dot + 1 + n).replace(".", "")); if (head % 2n === 1n) head += 1n;
    return Math.sign(x) * Number((Number(head) / Math.pow(10, n)).toFixed(n));
  }
  return Number(x.toFixed(n));
}
export const r2 = (x: number) => pyRoundN(x, 2);
/** Python str.title(): a letter after a non-letter is a capital, every other letter small */
export function pyTitle(s: string): string { let out = ""; let prev = false; for (const ch of s) { const isL = ch.toLowerCase() !== ch.toUpperCase(); out += isL ? (prev ? ch.toLowerCase() : ch.toUpperCase()) : ch; prev = isL; } return out; }
export const isUpper = (s: string) => /[A-Z]/.test(s) && s === s.toUpperCase();
export const isLower = (s: string) => /[a-z]/.test(s) && s === s.toLowerCase();
/** valid ISO date (first 10 characters), or null */
export function isoDate(s: unknown, minY = 0, maxY = 9999): string | null {
  const t = String(s ?? "").slice(0, 10); if (!/^\d{4}-\d{2}-\d{2}$/.test(t)) return null;
  const d = new Date(t + "T00:00:00Z"); if (isNaN(d.getTime()) || d.toISOString().slice(0, 10) !== t) return null;
  const y = d.getUTCFullYear(); return y >= minY && y <= maxY ? t : null;
}
export const dayDiff = (a: string, b: string) => Math.round((Date.parse(a + "T00:00:00Z") - Date.parse(b + "T00:00:00Z")) / 86400000);
export const addDays = (a: string, n: number) => new Date(Date.parse(a + "T00:00:00Z") + n * 86400000).toISOString().slice(0, 10);
export const chunk = <T,>(a: T[], n: number): T[][] => { const o: T[][] = []; for (let i = 0; i < a.length; i += n) o.push(a.slice(i, i + n)); return o; };
/** Python 3.12 sum() of floats (compensated), so the totals match the one-time loader digit for digit */
export function pySum(a: number[]): number { let s = 0, c = 0; for (const x of a) { const t = s + x; if (Math.abs(s) >= Math.abs(x)) c += (s - t) + x; else c += (x - t) + s; s = t; } return s + c; }

/** The moment a record was made in the ERP, as "YYYY-MM-DD HH:MM:SS" (the ERP's own clock), or "" when the ERP kept no time.
 *  Looks first at "<dateCol>__ts" (the bridge sends the full date and time of every ERP date column), then at columns named like a time
 *  (time, created, entered, stamp ...); a bare time such as "14:32" is joined to the record's date. */
export function erpTime(r: Row, dateCol: string): string {
  const day = String(r[dateCol] ?? "").slice(0, 10), hasDay = /^\d{4}-\d{2}-\d{2}$/.test(day);
  const full = (v: string) => { const m = /^(\d{4}-\d{2}-\d{2})[T ](\d{2}):(\d{2})(?::(\d{2}))?/.exec(v.trim()); return m ? `${m[1]} ${m[2]}:${m[3]}:${m[4] || "00"}` : ""; };
  const own = full(String(r[dateCol + "__ts"] ?? "")); if (own && own.slice(11) !== "00:00:00") return own;
  let bare = "";
  for (const k of Object.keys(r)) {
    if (k.endsWith("__ts") || !/(time|created|entered|stamp|modified|sysdate|logdt|entry(date|dt|time|on))/i.test(k)) continue;
    const v = String(r[k] ?? "").trim(); if (!v) continue;
    const f = full(v); if (f && f.slice(11) !== "00:00:00") return f;            // a full date and time column
    const t = /^(\d{1,2}):(\d{2})(?::(\d{2}))?(?:\s*([AaPp][Mm]))?$/.exec(v);    // a time of day only
    if (t && !bare) { let h = Number(t[1]); const ap = (t[4] || "").toUpperCase(); if (ap === "PM" && h < 12) h += 12; if (ap === "AM" && h === 12) h = 0; if (h < 24) bare = `${String(h).padStart(2, "0")}:${t[2]}:${t[3] || "00"}`; }
  }
  return hasDay && bare ? `${day} ${bare}` : "";
}
