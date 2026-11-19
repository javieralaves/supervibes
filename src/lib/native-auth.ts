import "server-only";

import * as z from "zod";

/**
 * Sign-in for the Mac app. Google won't sign in inside an embedded web view, so the app opens
 * /api/native/start in the system's sign-in sheet (ASWebAuthenticationSession):
 *
 *   1. start:   begins Google sign-in, coming back to finish.
 *   2. finish:  makes a session just for the app, mints a one-time token for it, and redirects
 *               to supervibes://auth?token=…&state=…, which the sheet hands to the app alone.
 *   3. The app trades the token at /api/auth/one-time-token/verify for its session token,
 *      keeps it in the Keychain, and sends it as `Authorization: Bearer …` from then on.
 *   4. handoff: the app's web view loads this with a fresh one-time token to get the same
 *               session as a cookie, then goes on to the page it asked for.
 */

/** The URL scheme the sign-in sheet listens for. Must match the Mac app. */
export const NATIVE_SCHEME = "supervibes";

/** The user agent recorded on sessions made for the app, so they can be told apart later. */
export const NATIVE_USER_AGENT = "Supervibes for Mac";

/** Random value from the app, echoed back so it can tell the callback answers its own request. */
export const stateSchema = z.string().regex(/^[A-Za-z0-9_-]{16,128}$/);

/** Redirect into the app. Only `supervibes://auth` is used. */
export function redirectToApp(params: Record<string, string>): Response {
  const url = new URL(`${NATIVE_SCHEME}://auth`);
  for (const [key, value] of Object.entries(params)) url.searchParams.set(key, value);
  return new Response(null, {
    status: 302,
    headers: { Location: url.toString(), "Cache-Control": "no-store" },
  });
}

/** A redirect that also carries the cookies better-auth set on `from` (session, OAuth state). */
export function redirectWithCookies(location: string, from: Response): Response {
  const response = new Response(null, {
    status: 302,
    headers: { Location: location, "Cache-Control": "no-store" },
  });
  for (const cookie of from.headers.getSetCookie()) response.headers.append("Set-Cookie", cookie);
  return response;
}

/** better-auth's error codes are short snake_case words; anything else is reported as "failed". */
export function errorCode(value: string | null): string {
  return value && /^[a-z_]{1,64}$/i.test(value) ? value.toLowerCase() : "failed";
}
