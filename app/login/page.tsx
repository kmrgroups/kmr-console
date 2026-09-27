import { redirect } from "next/navigation";
import { getStaff } from "@/lib/auth";
import { LoginForm } from "./LoginForm";

export const metadata = { title: "Sign in" };

export default async function LoginPage() {
  if (await getStaff()) redirect("/");
  return (
    <div className="authwrap">
      <div className="authcard">
        <h1>KMR Console</h1>
        <p className="sub">Customers, licences and products of KMR Group of Companies. KMR staff only.</p>
        <LoginForm />
      </div>
    </div>
  );
}
