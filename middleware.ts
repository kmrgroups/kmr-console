import { NextResponse, type NextRequest } from "next/server";
import { createServerClient } from "@supabase/ssr";
import { authCookieOptions } from "@/lib/supabase/cookie-options";

// Every Console page needs a signed-in user; staff membership is checked on the page itself.

/** Absolute address on the host the visitor used (www.kmr-groups.com behind the website's forwarding),
 *  never the app's own internal Vercel address — middleware redirects must be absolute. */
function publicUrl(request: NextRequest, path: string): URL {
  const host = request.headers.get("x-forwarded-host") || request.headers.get("host") || request.nextUrl.host;
  const proto = request.headers.get("x-forwarded-proto") || (host.startsWith("localhost") || host.startsWith("127.") ? "http" : "https");
  return new URL(`${request.nextUrl.basePath}${path}`, `${proto.split(",")[0]}://${host.split(",")[0]}`);
}

// Public: each invoice's pay link and the Razorpay endpoints (customers are not Console users)
const PUBLIC = /^\/(pay\/[a-f0-9]+|api\/pay\/(order|verify|webhook))\/?$/;

export async function middleware(request: NextRequest) {
  if (PUBLIC.test(request.nextUrl.pathname)) return NextResponse.next();
  let response = NextResponse.next({ request });
  const supabase = createServerClient(process.env.NEXT_PUBLIC_SUPABASE_URL!, process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!, {
    cookieOptions: authCookieOptions,
    cookies: {
      getAll: () => request.cookies.getAll(),
      setAll: (list) => {
        list.forEach(({ name, value }) => request.cookies.set(name, value));
        response = NextResponse.next({ request });
        list.forEach(({ name, value, options }) => response.cookies.set(name, value, options));
      },
    },
  });
  const { data: { user } } = await supabase.auth.getUser();
  if (!user && request.nextUrl.pathname !== "/login") {
    // relative Location: stay on www.kmr-groups.com behind the website's forwarding
    return NextResponse.redirect(publicUrl(request, "/login"), 307);
  }
  return response;
}
export const config = { matcher: ["/((?!api/cron|_next/static|_next/image|favicon.ico|.*\\.(?:png|svg|ico)$).*)"] };
