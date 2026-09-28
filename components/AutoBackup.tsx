"use client";
import { useEffect, useState } from "react";
import { p } from "@/lib/base-path";

/**
 * Daily backup to the administrator's computer: the platform saves a backup of the company every night at
 * 12 AM (India time); the first time an administrator opens the Console after that, it downloads automatically.
 * It can be switched off on this computer under Settings → Data & backups.
 */
export function AutoBackup({ company }: { company: string }) {
  const [done, setDone] = useState<string | null>(null);
  useEffect(() => {
    if (localStorage.getItem("kmr-console-auto-backup-off") === "1") return;
    fetch(p("/api/data/backup?latest=1")).then((r) => (r.ok ? r.json() : null)).then((j) => {
      const date = j?.date as string | null;
      const key = `kmr-console-auto-backup:${company}`;
      if (!date || localStorage.getItem(key) === date) return;
      const f = document.createElement("iframe"); f.style.display = "none"; f.src = p(`/api/data/backup?date=${date}`); document.body.append(f);
      setTimeout(() => f.remove(), 60000);
      localStorage.setItem(key, date); setDone(date);
    }).catch(() => {});
  }, [company]);
  if (!done) return null;
  return <div className="alert ok" style={{ marginBottom: 16 }}>Last night&apos;s backup ({done}) was downloaded to this computer. Keep it somewhere safe.</div>;
}

export function AutoBackupToggle() {
  const [off, setOff] = useState(false);
  useEffect(() => setOff(localStorage.getItem("kmr-console-auto-backup-off") === "1"), []);
  return (
    <label className="check">
      <input type="checkbox" checked={!off} onChange={(e) => { const v = !e.target.checked; setOff(v); localStorage.setItem("kmr-console-auto-backup-off", v ? "1" : "0"); }} />
      <span>Download the latest backup to <b>this computer</b> automatically once a day</span>
    </label>
  );
}
