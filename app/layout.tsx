import "./globals.css";
import type { Metadata } from "next";
import { Suspense } from "react";
import { PoweredBy } from "@/components/PoweredBy";
import { NavProgress } from "@/components/NavProgress";

export const metadata: Metadata = {
  title: { default: "KMR Console", template: "%s · KMR Console" },
  robots: { index: false, follow: false },
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body style={{ ["--brand" as string]: "#1F3A5F", ["--accent" as string]: "#E07A1F" }}>
        <Suspense fallback={null}><NavProgress /></Suspense>
        {children}
        <PoweredBy />
      </body>
    </html>
  );
}
