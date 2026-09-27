"use client";
import { useEffect, useState } from "react";
import { usePathname } from "next/navigation";
import { CopyLink } from "./ActionForm";
import { clearFlash } from "./flash-actions";

type Msg = { ok?: string; error?: string; link?: string };

// Survives the component being re-created. After the cookie is cleared the page re-renders
// (and, with loading screens, may re-mount this component) with msg = null — keep showing the
// last message on the same page until the user navigates away.
let last: { msg: Msg; path: string } | null = null;

export function Flash({ msg }: { msg: Msg | null }) {
  const path = usePathname();
  const [shown, setShown] = useState<Msg | null>(msg ?? (last && last.path === path ? last.msg : null));
  useEffect(() => {
    if (msg) {
      last = { msg, path };
      setShown(msg);
      clearFlash();
    } else if (last && last.path !== path) {
      last = null;
      setShown(null);
    }
  }, [msg, path]);
  if (!shown) return null;
  return (
    <div className="stack" style={{ marginBottom: 16 }}>
      {shown.error && <div className="alert error" role="alert">{shown.error}</div>}
      {shown.ok && <div className="alert ok" role="status">{shown.ok}</div>}
      {shown.link && <CopyLink link={shown.link} />}
    </div>
  );
}
