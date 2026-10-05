/** @type {import('next').NextConfig} */
const basePath = (process.env.NEXT_PUBLIC_BASE_PATH || "").replace(/\/+$/, "") || undefined;
const allowedOrigins = (process.env.ALLOWED_ORIGINS || "www.kmr-groups.com").split(",").map((s) => s.trim()).filter(Boolean);

export default {
  basePath,
  poweredByHeader: false,
  // the quotation PDF reads its fonts and the built-in letterhead from ./assets
  outputFileTracingIncludes: { "/api/quotes/[id]/pdf": ["./assets/**/*"] },
  experimental: { serverActions: { allowedOrigins, bodySizeLimit: "6mb" } },
  async headers() {
    return [{ source: "/(.*)", headers: [
      { key: "X-Content-Type-Options", value: "nosniff" },
      { key: "Referrer-Policy", value: "strict-origin-when-cross-origin" },
      { key: "X-Frame-Options", value: "DENY" },
      { key: "X-Robots-Tag", value: "noindex, nofollow" },
    ] }];
  },
};
