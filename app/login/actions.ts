"use server";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

export interface LoginState { error?: string }

export async function login(_: LoginState, form: FormData): Promise<LoginState> {
  const email = String(form.get("email") || "").trim().toLowerCase();
  const password = String(form.get("password") || "");
  if (!email || !password) return { error: "Enter your email and password." };
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
