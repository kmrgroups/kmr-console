// Parsing of what fingerprint / face machines send. Kept free of any framework so it can be tested on its own.
// Time is the machine's own clock ("2026-10-14 09:05:00"); the database reads it in the company's time zone.

export type Punch = { bio_id: string; time: string; verify: string; direction: "in" | "out" | null };

/** ZKTeco / eSSL / Realtime "verify" codes of the push (ADMS) protocol */
export function verifyName(code: string): string {
  switch (code.trim()) {
    case "1": return "finger";
    case "15": case "16": case "17": case "18": return "face";
    case "2": case "3": case "4": return "card";
    case "0": return "password";
    case "25": return "palm";
    default: return "other";
  }
}

/** Status 0 = check-in, 1 = check-out (3 / 4 = OT-in / break-in are treated as in; 2 / 5 as out) */
export function directionOf(code: string): "in" | "out" | null {
  switch (code.trim()) {
    case "0": case "3": case "4": return "in";
    case "1": case "2": case "5": return "out";
    default: return null;
  }
}

/** Body of POST /iclock/cdata?table=ATTLOG: one punch per line, tab separated: PIN, time, status, verify, work code … */
export function parseAttLog(body: string): { punches: Punch[]; bad: number } {
  const punches: Punch[] = []; let bad = 0;
  for (const raw of body.split(/\r?\n/)) {
    const line = raw.trim(); if (!line) continue;
    const f = line.split(/\t/);
    // some firmwares use spaces between the fields instead of tabs: "12 2026-10-14 09:05:00 0 1 0 0 0"
    const g = f.length >= 2 ? f : line.split(/\s+/);
    let pin = (g[0] || "").trim(), time = (g[1] || "").trim(), rest = g.slice(2);
    if (f.length < 2 && g.length >= 3 && /^\d{4}-\d{2}-\d{2}$/.test(g[1]) && /^\d{2}:\d{2}(:\d{2})?$/.test(g[2])) { time = `${g[1]} ${g[2]}`; rest = g.slice(3); }
    if (!pin || !/^\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}(:\d{2})?$/.test(time)) { bad++; continue; }
    punches.push({ bio_id: pin, time: time.replace("T", " "), verify: verifyName(rest[1] ?? ""), direction: directionOf(rest[0] ?? "") });
  }
  return { punches, bad };
}

/** What the machine is told when it asks for its settings (GET /iclock/cdata?SN=…&options=all) */
export function admsOptions(sn: string): string {
  return [
    `GET OPTION FROM: ${sn}`, "ErrorDelay=30", "Delay=10", "TransTimes=00:00;14:05", "TransInterval=1",
    "TransFlag=TransData AttLog\tOpLog\tAttPhoto\tEnrollUser\tChgUser\tEnrollFP\tChgFP\tUserPic", "Realtime=1", "Encrypt=0", "",
  ].join("\n");
}

/** JSON push from a bridge program or a machine with an HTTP push: array, {punches:[…]} or one punch. Field names are forgiving. */
export function parseJsonPunches(body: unknown): Record<string, unknown>[] {
  const b = body as { punches?: unknown; punch?: unknown; records?: unknown; data?: unknown } | unknown[] | null;
  const list = Array.isArray(b) ? b : Array.isArray(b?.punches) ? b.punches : Array.isArray(b?.records) ? b.records : Array.isArray(b?.data) ? b.data : b?.punch ? [b.punch] : b && typeof b === "object" ? [b] : [];
  return (list as Record<string, unknown>[]).filter((x) => x && typeof x === "object").slice(0, 5000);
}
