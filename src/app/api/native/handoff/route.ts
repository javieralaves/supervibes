import { auth } from "@/lib/auth";
import { redirectWithCookies, safeNext } from "@/lib/native-auth";

/**
 * Step 4 of the Mac app's sign-in (see lib/native-auth.ts). The app's web view loads this with a
 * fresh one-time token for the app's session; it comes away with that session as a cookie and
 * continues to `next`.
 */
export async function GET(request: Request) {
  const url = new URL(request.url);
  const token = url.searchParams.get("token") ?? "";
  const next = safeNext(url.searchParams.get("next"), url.origin);

  const verified = await auth.api
    .verifyOneTimeToken({ body: { token }, headers: request.headers, asResponse: true })
    .catch(() => null);
  if (!verified?.ok) return redirectWithCookies(new URL("/sign-in?error=handoff", url).toString(), new Response());

  return redirectWithCookies(new URL(next, url).toString(), verified);
}
