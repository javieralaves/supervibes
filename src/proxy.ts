import { getSessionCookie } from "better-auth/cookies";
import { NextResponse, type NextRequest } from "next/server";

// Fast first pass: no session cookie at all → straight to /sign-in.
// This only checks that the cookie exists. Pages still validate the session
// on the server with requireUser().
export function proxy(request: NextRequest) {
  if (!getSessionCookie(request)) {
    return NextResponse.redirect(new URL("/sign-in", request.url));
  }
  return NextResponse.next();
}

export const config = {
  matcher: [
    // Everything except auth endpoints (including the Mac app's sign-in), the API (which checks
    // bearer tokens itself), the connections callback (which can finish a Mac app flow in a
    // browser that isn't signed in, and checks the session itself otherwise), the sign-in page,
    // health check and static assets.
    "/((?!api/auth|api/native|api/v1|api/connections/callback|api/health|api/cron|sign-in|_next/static|_next/image|favicon\\.ico|.*\\.(?:svg|png|jpg|jpeg|gif|webp|ico)$).*)",
  ],
};
