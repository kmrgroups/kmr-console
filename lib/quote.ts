/** Quotations: shared by the builder (browser), the save action and the PDF (server). */

export type Basis = "one_time" | "per_month" | "per_year" | "per_user_month" | "per_user_year" | "per_day" | "per_hour" | "per_unit";

export const BASIS: Record<Basis, { label: string; qty: string; months: boolean }> = {
  one_time:       { label: "One-time",             qty: "Qty",   months: false },
  per_month:      { label: "Per month",            qty: "Qty",   months: true },
  per_year:       { label: "Per year",             qty: "Qty",   months: false },
  per_user_month: { label: "Per user / month",     qty: "Users", months: true },
  per_user_year:  { label: "Per user / year",      qty: "Users", months: false },
  per_day:        { label: "Per day",              qty: "Days",  months: false },
  per_hour:       { label: "Per hour",             qty: "Hours", months: false },
  per_unit:       { label: "Per unit",             qty: "Units", months: false },
};

export type QuoteLine = {
  particulars: string;      // what it is
  detail?: string;          // one line under it
  basis: Basis;
  qty: number;              // users / days / units
  rate: number;             // price per basis unit, before GST
  months?: number;          // monthly bases: how many months
  product_code?: string | null;
  feature_id?: string | null; // set when the line is one chosen feature of an app
};
export type ScopeRow = { module: string; capability: string };

export type QuoteInput = {
  id?: string;
  customer_id?: string | null;
  lead_id?: string | null;
  to_name: string; to_attn?: string; to_address?: string; to_gstin?: string; to_email?: string; to_phone?: string;
  subject: string; intro?: string;
  scope: ScopeRow[]; lines: QuoteLine[];
  includes?: string; terms?: string;
  discount_pct: number; gst_rate: number;
  quote_date: string; valid_until?: string | null;
  notes?: string;
};

const r2 = (n: number) => Math.round((Number(n) || 0) * 100) / 100;

export function lineAmount(l: QuoteLine): number {
  const qty = Number(l.qty) || 0, rate = Number(l.rate) || 0;
  return r2(qty * rate * (BASIS[l.basis]?.months ? Math.max(1, Number(l.months) || 1) : 1));
}

/** the "Basis" column as printed, e.g. "25 users × 12 months" */
export function basisText(l: QuoteLine, seat = "users"): string {
  const b = BASIS[l.basis] ?? BASIS.one_time, q = Number(l.qty) || 0, m = Math.max(1, Number(l.months) || 1);
  const unit = l.basis.startsWith("per_user") ? seat : b.qty.toLowerCase();
  if (l.basis === "one_time") return q === 1 ? "One-time" : `${q} × one-time`;
  if (l.basis === "per_user_month") return `${q} ${unit} × ${m} month${m === 1 ? "" : "s"}`;
  if (l.basis === "per_month") return `${q > 1 ? `${q} × ` : ""}${m} month${m === 1 ? "" : "s"}`;
  if (l.basis === "per_user_year") return `${q} ${unit} × 1 year`;
  if (l.basis === "per_year") return q === 1 ? "12 months" : `${q} × 12 months`;
  return `${q} ${unit}`;
}

export function totals(q: Pick<QuoteInput, "lines" | "discount_pct" | "gst_rate">) {
  const subtotal = r2(q.lines.reduce((a, l) => a + lineAmount(l), 0));
  const discount = r2(subtotal * Math.min(100, Math.max(0, Number(q.discount_pct) || 0)) / 100);
  const taxable = r2(subtotal - discount);
  const gst = r2(taxable * Math.max(0, Number(q.gst_rate) || 0) / 100);
  return { subtotal, discount, taxable, gst, total: r2(taxable + gst) };
}

export const inr = (n: number, sym = true) =>
  (sym ? "₹" : "") + (Number(n) || 0).toLocaleString("en-IN", { minimumFractionDigits: Number(n) % 1 ? 2 : 0, maximumFractionDigits: 2 });

/** Indian-system amount in words: "Rupees Three Lakh Twelve Thousand Seven Hundred Only" */
export function inWords(n: number): string {
  const a = ["", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine", "Ten", "Eleven", "Twelve", "Thirteen", "Fourteen", "Fifteen", "Sixteen", "Seventeen", "Eighteen", "Nineteen"];
  const t = ["", "", "Twenty", "Thirty", "Forty", "Fifty", "Sixty", "Seventy", "Eighty", "Ninety"];
  const two = (x: number) => (x < 20 ? a[x] : `${t[Math.floor(x / 10)]}${x % 10 ? " " + a[x % 10] : ""}`);
  const three = (x: number) => [x >= 100 ? `${a[Math.floor(x / 100)]} Hundred` : "", two(x % 100)].filter(Boolean).join(" ");
  const whole = Math.floor(Math.abs(n)), paise = Math.round((Math.abs(n) - whole) * 100);
  if (!whole && !paise) return "Rupees Zero Only";
  const parts: string[] = []; let x = whole;
  const crore = Math.floor(x / 1e7); x %= 1e7; const lakh = Math.floor(x / 1e5); x %= 1e5; const th = Math.floor(x / 1e3); x %= 1e3;
  if (crore) parts.push(`${crore >= 1000 ? inWords(crore).replace(/^Rupees |\sOnly$/g, "") : three(crore) || two(crore)} Crore`);
  if (lakh) parts.push(`${two(lakh)} Lakh`); if (th) parts.push(`${two(th)} Thousand`); if (x) parts.push(three(x));
  return `Rupees ${parts.join(" ")}${paise ? ` and ${two(paise)} Paise` : ""} Only`;
}

export function addDays(d: string, n: number): string {
  const x = new Date(d + "T00:00:00Z"); x.setUTCDate(x.getUTCDate() + n); return x.toISOString().slice(0, 10);
}
