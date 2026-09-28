import { NextResponse, type NextRequest } from "next/server";
import { createServerClient } from "@supabase/ssr";
import { authCookieOptions } from "@/lib/supabase/cookie-options";

// Every Console page needs a signed-in user; staff membership is checked on the page itself.
export async function middleware(request: NextRequest) {
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
    return new NextResponse(null, { status: 307, headers: { Location: `${request.nextUrl.basePath}/login` } });
  }
  return response;
}
export const config = { matcher: ["/((?!api/cron|_next/static|_next/image|favicon.ico|.*\\.(?:png|svg|ico)$).*)"] };
