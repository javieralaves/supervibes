import { auth } from "@/lib/auth";
import { errorCode, redirectToApp, redirectWithCookies, stateSchema } from "@/lib/native-auth";

/** Step 1 of the Mac app's sign-in (see lib/native-auth.ts): begin Google sign-in. */
export async function GET(request: Request) {
  const state = stateSchema.safeParse(new URL(request.url).searchParams.get("state"));
  if (!state.success) return new Response("Missing or invalid state.", { status: 400 });

  const finish = `/api/native/finish?state=${state.data}`;
  const started = await auth.api.signInSocial({
    body: { provider: "google", callbackURL: finish, errorCallbackURL: finish },
    headers: request.headers,
    asResponse: true,
  });

  const body = (await started.json().catch(() => null)) as { url?: string } | null;
  if (!started.ok || !body?.url) {
    console.error("[native] couldn't start Google sign-in", started.status, body);
    return redirectToApp({ state: state.data, error: errorCode(null) });
  }

  // Carries better-auth's OAuth state cookie, which the Google callback checks.
  return redirectWithCookies(body.url, started);
}
