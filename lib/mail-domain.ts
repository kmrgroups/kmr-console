import "server-only";
/** Sending domains at the mail provider (Resend). The API key must be a full-access key. */
const API = () => (process.env.RESEND_API_URL || "https://api.resend.com/emails").replace(/\/emails\/?$/, "");
export type DnsRecord = { record?: string; name: string; type: string; value: string; ttl?: string; priority?: number; status?: string };
export type DomainInfo = { id: string; status: string; records: DnsRecord[] };

async function call(path: string, method: string, body?: unknown): Promise<Record<string, unknown>> {
  const key = process.env.RESEND_API_KEY;
  if (!key) throw new Error("Mail is not set up on the server yet (RESEND_API_KEY).");
  const r = await fetch(API() + path, { method, headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json" }, body: body ? JSON.stringify(body) : undefined, signal: AbortSignal.timeout(15000) });
  const j = (await r.json().catch(() => ({}))) as Record<string, unknown>;
  if (!r.ok) throw new Error(String(j.message || j.error || `Mail provider answered ${r.status}`));
  return j;
}
const info = (j: Record<string, unknown>): DomainInfo => ({ id: String(j.id), status: String(j.status || "pending"), records: (Array.isArray(j.records) ? j.records : []) as DnsRecord[] });

export async function addDomain(name: string): Promise<DomainInfo> {
  try { const j = await call("/domains", "POST", { name }); return await getDomain(String(j.id)); }
  catch (e) {
    // already added earlier (e.g. by the customer's own HRM): find it
    const list = await call("/domains", "GET").catch(() => ({}));
    const hit = (Array.isArray((list as { data?: unknown[] }).data) ? (list as { data: { id: string; name: string }[] }).data : []).find((d) => d.name === name);
    if (hit) return getDomain(hit.id);
    throw e;
  }
}
export async function getDomain(id: string): Promise<DomainInfo> { return info(await call(`/domains/${encodeURIComponent(id)}`, "GET")); }
export async function verifyDomain(id: string): Promise<DomainInfo> { await call(`/domains/${encodeURIComponent(id)}/verify`, "POST").catch(() => null); return getDomain(id); }
export async function removeDomain(id: string): Promise<void> { await call(`/domains/${encodeURIComponent(id)}`, "DELETE").catch(() => null); }
