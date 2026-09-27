"use client";
import { useActionState } from "react";
import { login, type LoginState } from "./actions";
import { PasswordInput } from "@/components/PasswordInput";

export function LoginForm() {
  const [state, action, pending] = useActionState<LoginState, FormData>(login, {});
  return (
    <form action={action} className="stack">
      <label className="field">Email<input name="email" type="email" autoComplete="username" required /></label>
      <label className="field">Password<PasswordInput name="password" autoComplete="current-password" required /></label>
      {state.error && <div className="alert error">{state.error}</div>}
      <button className="btn block" disabled={pending}>{pending ? "Signing in…" : "Sign in"}</button>
    </form>
  );
}
