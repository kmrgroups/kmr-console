"use client";
import { startTransition, useActionState, useEffect, useRef } from "react";
import type { ActionState } from "@/lib/action-state";

/**
 * Wrapper for a server-action form that shows the success / error message and
 * any generated link (with a copy button) under the form.
 *
 * Submits through onSubmit rather than the `action` prop so that React does not
 * clear what the user typed when the server returns an error.
 */
export function ActionForm({
  action, children, submitLabel, pendingLabel, className, confirm, variant, hidden, resetOnSuccess,
}: {
  action: (s: ActionState, f: FormData) => Promise<ActionState>;
  children?: React.ReactNode;
  submitLabel: string;
  pendingLabel?: string;
  className?: string;
  confirm?: string;
  variant?: "secondary" | "danger" | "accent";
  hidden?: Record<string, string>;
  resetOnSuccess?: boolean;
}) {
  const [state, formAction, pending] = useActionState<ActionState, FormData>(action, {});
  const ref = useRef<HTMLFormElement>(null);
  useEffect(() => {
    if (resetOnSuccess && state.ok) ref.current?.reset();
  }, [state, resetOnSuccess]);

  return (
    <form
      ref={ref}
      className={className ?? "stack"}
      onSubmit={(e) => {
        e.preventDefault();
        if (confirm && !window.confirm(confirm)) return;
        const data = new FormData(e.currentTarget);
        startTransition(() => formAction(data));
      }}
    >
      {hidden && Object.entries(hidden).map(([k, v]) => <input key={k} type="hidden" name={k} value={v} />)}
      {children}
      <div><button className={`btn${variant ? " " + variant : ""}`} disabled={pending}>{pending ? pendingLabel ?? "Please wait…" : submitLabel}</button></div>
      {state.error && <div className="alert error" role="alert">{state.error}</div>}
      {state.ok && !state.flashed && <div className="alert ok" role="status">{state.ok}</div>}
      {state.link && !state.flashed && <CopyLink link={state.link} />}
    </form>
  );
}

export function CopyLink({ link }: { link: string }) {
  return (
    <div className="stack" style={{ gap: 6 }}>
      <small>You can also share this link directly (valid for one person only):</small>
      <div className="copybox">
        <input readOnly value={link} onFocus={(e) => e.target.select()} />
        <button type="button" className="btn secondary small" onClick={() => navigator.clipboard?.writeText(link)}>Copy</button>
      </div>
    </div>
  );
}
