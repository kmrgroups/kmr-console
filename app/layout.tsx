import "./globals.css";
import type { Metadata } from "next";
import { Suspense } from "react";
import { PoweredBy } from "@/components/PoweredBy";
import { NavProgress } from "@/components/NavProgress";
import { PopupCloser } from "@/components/PopupCloser";

import { platformBrand } from "@/lib/brand";

// KMR's logo (Console → KMR branding) is also the browser-tab icon
export async function generateMetadata(): Promise<Metadata> {
  const b = await platformBrand();
  return {
    title: { default: "KMR Console", template: "%s · KMR Console" },
    robots: { index: false, follow: false },
    ...(b.logo_url ? { icons: { icon: b.logo_url, apple: b.logo_url } } : {}),
  };
}

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body style={{ ["--brand" as string]: "#1F3A5F", ["--accent" as string]: "#E07A1F" }}>
        <Suspense fallback={null}><NavProgress /></Suspense>
        {children}
        <PopupCloser />
        <PoweredBy />
      </body>
    </html>
  );
}
