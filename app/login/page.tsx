import { redirect } from "next/navigation";
import { getStaff } from "@/lib/auth";
import { FusionScene } from "@/components/fusion/FusionScene";
import "@/components/fusion/fusion.css";
import { LoginForm } from "./LoginForm";
import { platformBrand } from "@/lib/brand";

export const metadata = { title: "Sign in" };

export default async function LoginPage() {
  if (await getStaff()) redirect("/");
  const brand = await platformBrand();
  return (
    <div className="fz-split">
      <FusionScene variant="console" chip="KMR Console" headline="One console," em="every customer." sub="Customers, licences, support and releases of KMR Group of Companies."
        tags={["HRM Suite", "Balloon Inspector", "Process Documents"]} />
      <section className="fz-panel">
        <div className="fz-form">
          <div className="fz-co">
            {brand.logo_url ? <img src={brand.logo_url} alt="KMR Group of Companies" /> : <span className="fb">K</span>}
            <div>KMR Group of Companies<small>KMR Console · staff only</small></div>
          </div>
          <h2>Welcome back</h2>
          <p className="fz-sub">Sign in with your KMR staff account.</p>
          <LoginForm />
          <p className="fz-note">Restricted to KMR staff · activity is logged</p>
        </div>
      </section>
    </div>
  );
}
