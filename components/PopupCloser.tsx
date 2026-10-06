"use client";
import { useEffect } from "react";

/**
 * Makes every button-style <details> panel in the Console behave like a proper popup:
 *  • opening one closes any other open popup (no stacked, overlapping panels)
 *  • a click outside, or the Esc key, closes a popup; each popup gets a visible Close button
 *  • inline panels (no floating box) are closed by Esc or by their own button, never by clicking elsewhere
 * (A form inside a panel also closes it when it saves — see ActionForm.)
 */
export function PopupCloser() {
  useEffect(() => {
    const isPop = (d: Element) => !!d.querySelector(":scope > .editpop");
    const panels = () => Array.from(document.querySelectorAll<HTMLDetailsElement>("details")).filter((d) => d.querySelector(":scope > summary.btn"));
    const closeBtn = (d: HTMLDetailsElement) => {
      const pop = d.querySelector<HTMLElement>(":scope > .editpop");
      if (!pop || pop.querySelector(":scope > .pop-close")) return;
      const b = document.createElement("button");
      b.type = "button"; b.className = "pop-close"; b.textContent = "✕ Close"; b.setAttribute("aria-label", "Close");
      b.addEventListener("click", () => { d.open = false; });
      pop.prepend(b);
    };
    const onToggle = (e: Event) => {
      const d = e.target as HTMLDetailsElement;
      if (!(d instanceof HTMLDetailsElement) || !d.open || !isPop(d)) return;
      closeBtn(d);
      panels().forEach((o) => { if (o !== d && o.open && isPop(o)) o.open = false; });
    };
    const onDown = (e: MouseEvent) => {
      const t = e.target as Node;
      panels().forEach((d) => { if (d.open && isPop(d) && !d.contains(t)) d.open = false; });
    };
    const onKey = (e: KeyboardEvent) => { if (e.key === "Escape") panels().forEach((d) => { if (d.open) d.open = false; }); };
    document.addEventListener("toggle", onToggle, true);
    document.addEventListener("mousedown", onDown);
    document.addEventListener("keydown", onKey);
    return () => { document.removeEventListener("toggle", onToggle, true); document.removeEventListener("mousedown", onDown); document.removeEventListener("keydown", onKey); };
  }, []);
  return null;
}
