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
    // Everything except auth endpoints, the sign-in page, health check and static assets.
    "/((?!api/auth|api/health|sign-in|_next/static|_next/image|favicon\\.ico|.*\\.(?:svg|png|jpg|jpeg|gif|webp|ico)$).*)",
  ],
};
