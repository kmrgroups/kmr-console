import { redirect } from "next/navigation";
import { getStaff } from "@/lib/auth";
import { BrandScene } from "@/components/brand/BrandScene";
import { LoginForm } from "./LoginForm";

export const metadata = { title: "Sign in" };

export default async function LoginPage() {
  if (await getStaff()) redirect("/");
  return (
    <div className="kmr-login">
      <BrandScene />
      <div className="kmr-login-panel">
        <div className="kmr-login-card">
          <div className="eyebrow">KMR Console</div>
          <h1>Welcome back</h1>
          <p className="sub">Customers, licences and products of KMR Group of Companies.</p>
          <LoginForm />
          <p className="note">Restricted to KMR staff · activity is logged</p>
        </div>
      </div>
    </div>
  );
}
