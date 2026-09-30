"use server";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { clientIp, rateOk } from "@/lib/rate";

export interface LoginState { error?: string }

export async function login(_: LoginState, form: FormData): Promise<LoginState> {
  const email = String(form.get("email") || "").trim().toLowerCase();
  const password = String(form.get("password") || "");
  if (!email || !password) return { error: "Enter your email and password." };
  const ip = await clientIp();
  if (!(await rateOk(`console-login:${ip}`, 20, 900)) || !(await rateOk(`console-login:${email}`, 8, 900)))
    return { error: "Too many sign-in attempts. Please wait 15 minutes and try again." };
  const supabase = await createClient();
  const { data, error } = await supabase.auth.signInWithPassword({ email, password });
  if (error || !data.user) return { error: "Incorrect email or password." };
  const { data: staff } = await supabase.from("staff").select("active").eq("user_id", data.user.id).maybeSingle();
  if (!staff?.active) {
    await supabase.auth.signOut();
    return { error: "This account is not KMR Console staff." };
  }
  redirect("/");
}

export async function signOut() {
  const supabase = await createClient();
  await supabase.auth.signOut();
  redirect("/login");
}
