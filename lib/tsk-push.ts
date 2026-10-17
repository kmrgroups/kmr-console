import "server-only";
import webpush from "web-push";
import { createAdminClient } from "@/lib/supabase/admin";
import { env } from "@/lib/env";

/** ActionTrack: sends the notifications that are waiting (new task, comment, due, overdue) to the phones, tablets and computers that turned alerts on.
 *  Needs VAPID_PUBLIC_KEY and VAPID_PRIVATE_KEY (see docs/env.example.txt). Without them nothing is sent, and the bell inside the app still works. */
type Pending = { nid: string; title: string; body: string | null; task_id: string | null; slug: string; endpoint: string; p256dh: string; auth: string };

export function vapidReady(): boolean { return !!(process.env.VAPID_PUBLIC_KEY && process.env.VAPID_PRIVATE_KEY); }

export async function deliverPending(limit = 200): Promise<{ sent: number; dropped: number; waiting: number }> {
  if (!vapidReady()) return { sent: 0, dropped: 0, waiting: 0 };
  webpush.setVapidDetails(process.env.VAPID_SUBJECT || "mailto:info@kmr-groups.com", process.env.VAPID_PUBLIC_KEY!, process.env.VAPID_PRIVATE_KEY!);
  const db = createAdminClient().schema("public");
  const { data, error } = await db.rpc("kmr_tsk_push_take", { p_limit: limit });
  if (error) throw new Error(error.message);
  const rows = (data ?? []) as Pending[];
  let sent = 0, dropped = 0;
  await Promise.all(rows.map(async (r) => {
    const url = `${env.platformUrl}/it/tasks.html?kmr=1&co=${encodeURIComponent(r.slug)}#go=mine${r.task_id ? "&t=" + r.task_id : ""}`;
    try {
      await webpush.sendNotification({ endpoint: r.endpoint, keys: { p256dh: r.p256dh, auth: r.auth } }, JSON.stringify({ title: r.title, body: r.body ?? "", url, tag: r.task_id ?? r.nid }), { TTL: 60 * 60 * 24 });
      sent++;
    } catch (e) {
      const code = (e as { statusCode?: number }).statusCode;
      if (code === 404 || code === 410) { dropped++; await db.rpc("kmr_tsk_push_drop", { p_endpoint: r.endpoint }); }   // the device removed the app or revoked alerts
    }
  }));
  return { sent, dropped, waiting: rows.length };
}
