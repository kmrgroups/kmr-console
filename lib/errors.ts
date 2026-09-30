import "server-only";
import { createAdminClient } from "@/lib/supabase/admin";
import { alertEmail, sendMail } from "@/lib/mail";

/** Records a server error (de-duplicated in the database) and emails an alert only when it is new. */
export async function reportError(app: string, path: string, e: Error & { digest?: string }, where?: string) {
  const message = (e?.message || String(e)).slice(0, 1000);
  const { data: isNew } = await createAdminClient().schema("public").rpc("kmr_log_error", {
    p_app: app, p_path: path.slice(0, 300), p_message: message, p_digest: e?.digest ?? null, p_detail: [where, e?.stack].filter(Boolean).join("\n").slice(0, 4000),
  });
  if (isNew === true) {
    await sendMail({ kind: "error_alert", to: await alertEmail(), subject: `[${app}] Error: ${message.slice(0, 80)}`, heading: "Something went wrong on the server",
      paragraphs: ["This error is recorded in Console › System health. You get one email per error per hour."],
      rows: [["App", app], ["Page", path], ["Error", message.slice(0, 300)]] });
  }
}
