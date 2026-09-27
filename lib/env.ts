function required(name: string): string {
  const v = process.env[name];
  if (!v) throw new Error(`Missing environment variable ${name}. See .env.example.`);
  return v;
}
export const env = {
  get supabaseUrl() { return required("NEXT_PUBLIC_SUPABASE_URL"); },
  get supabaseAnonKey() { return required("NEXT_PUBLIC_SUPABASE_ANON_KEY"); },
  get serviceRoleKey() { return required("SUPABASE_SERVICE_ROLE_KEY"); },
  /** Where customers open the products, e.g. https://www.kmr-groups.com */
  get platformUrl() { return (process.env.PLATFORM_URL || "https://www.kmr-groups.com").replace(/\/+$/, ""); },
};
