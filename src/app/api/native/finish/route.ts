import { auth } from "@/lib/auth";
import { errorCode, NATIVE_USER_AGENT, redirectToApp, stateSchema } from "@/lib/native-auth";
import { getSession } from "@/lib/session";

/**
 * Step 2 of the Mac app's sign-in (see lib/native-auth.ts). Google sent the sign-in sheet back
 * here with a browser session. Make a separate session for the app, so signing out of one
 * doesn't sign out the other, and send the app a one-time token for it.
 */
export async function GET(request: Request) {
  const params = new URL(request.url).searchParams;
  const state = stateSchema.safeParse(params.get("state"));
  if (!state.success) return new Response("Missing or invalid state.", { status: 400 });

  if (params.has("error")) return redirectToApp({ state: state.data, error: errorCode(params.get("error")) });

  // Also checks ALLOWED_EMAILS.
  const session = await getSession();
  if (!session) return redirectToApp({ state: state.data, error: "not_signed_in" });

  try {
    const context = await auth.$context;
    const appSession = await context.internalAdapter.createSession(session.user.id, false, {
      userAgent: NATIVE_USER_AGENT,
    });
    const { token } = await auth.api.generateOneTimeToken({
      headers: new Headers({ authorization: `Bearer ${appSession.token}` }),
    });
    return redirectToApp({ state: state.data, token });
  } catch (error) {
    console.error("[native] couldn't finish sign-in", error);
    return redirectToApp({ state: state.data, error: errorCode(null) });
  }
}
