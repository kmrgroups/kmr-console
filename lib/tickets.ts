export const TICKET_TONE: Record<string, string> = { open: "warn", in_progress: "info", waiting_on_customer: "", resolved: "ok", closed: "" };
export const TICKET_LABEL: Record<string, string> = { open: "Open", in_progress: "In progress", waiting_on_customer: "Waiting on customer", resolved: "Resolved", closed: "Closed" };
export const PRIORITY_TONE: Record<string, string> = { low: "", normal: "", high: "warn", urgent: "danger" };
export function age(iso: string): string {
  const m = Math.round((Date.now() - Date.parse(iso)) / 60000);
  return m < 60 ? `${m} min` : m < 1440 ? `${Math.round(m / 60)} h` : `${Math.round(m / 1440)} d`;
}
