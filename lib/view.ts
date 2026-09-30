export const LICENCE_TONE: Record<string, string> = { trial: "info", pilot: "info", active: "ok", suspended: "danger", expired: "warn", cancelled: "" };
export const INVOICE_TONE: Record<string, string> = { draft: "", issued: "info", paid: "ok", cancelled: "danger" };
export const CUSTOMER_TONE: Record<string, string> = { lead: "", pilot: "info", active: "ok", inactive: "warn" };
export const today = () => new Date().toISOString().slice(0, 10);
export const addDays = (d: string, n: number) => new Date(Date.parse(d) + n * 864e5).toISOString().slice(0, 10);
export function effectiveStatus(l: { status: string; valid_until: string | null }): string {
  return l.valid_until && l.valid_until < today() && ["trial", "pilot", "active"].includes(l.status) ? "expired" : l.status;
}
