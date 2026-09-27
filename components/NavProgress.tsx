"use client";
import { useEffect, useState } from "react";
import { usePathname, useSearchParams } from "next/navigation";

/**
 * Instant feedback on every click: a thin bar at the top of the screen from the moment a link
 * is clicked until the next page is shown. Unlike loading.tsx screens it never re-creates the
 * page, so "Saved" messages and form results are not lost after an action.
 */
export function NavProgress() {
  const pathname = usePathname();
  const search = useSearchParams();
  const [busy, setBusy] = useState(false);

  // New page shown → hide the bar
  useEffect(() => setBusy(false), [pathname, search]);

  useEffect(() => {
    const onClick = (e: MouseEvent) => {
      if (e.defaultPrevented || e.button !== 0 || e.metaKey || e.ctrlKey || e.shiftKey || e.altKey) return;
      const a = (e.target as HTMLElement | null)?.closest?.("a");
      if (!a || a.target === "_blank" || a.hasAttribute("download")) return;
      const href = a.getAttribute("href");
      if (!href || href.startsWith("#") || href.startsWith("mailto:") || href.startsWith("tel:")) return;
      const url = new URL(a.href, location.href);
      if (url.origin !== location.origin || url.pathname.includes("/api/")) return;
      if (url.pathname === location.pathname && url.search === location.search) return;
      setBusy(true);
    };
    const onSubmit = (e: SubmitEvent) => {
      const f = e.target as HTMLFormElement;
      if ((f.method || "get").toLowerCase() === "get") setBusy(true); // filter forms navigate
    };
    document.addEventListener("click", onClick, true);
    document.addEventListener("submit", onSubmit, true);
    return () => {
      document.removeEventListener("click", onClick, true);
      document.removeEventListener("submit", onSubmit, true);
    };
  }, []);

  // Safety: never leave the bar stuck
  useEffect(() => {
    if (!busy) return;
    const t = setTimeout(() => setBusy(false), 15000);
    return () => clearTimeout(t);
  }, [busy]);

  return <div className={`navprogress${busy ? " on" : ""}`} role="progressbar" aria-hidden={!busy} aria-label="Loading" />;
}
