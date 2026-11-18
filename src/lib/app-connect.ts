import "server-only";

import { auth } from "@/lib/auth";
import { decryptJson, encryptJson } from "@/lib/crypto";
import type { OAuthFlow } from "@/lib/mcp-oauth";

/*
 * Connecting an app (Linear, GitHub, Granola) from the Mac app. The web flow keeps the OAuth
 * state in a cookie and needs a signed-in browser; the Mac app has neither in the browser that
 * runs the provider's consent page (the system sign-in sheet). Instead:
 *
 *   1. POST /api/v1/connections/{provider}/start (bearer) begins authorization and stores the flow
 *      here, keyed by its OAuth `state`, for ten minutes.
 *   2. The provider sends the sheet to /api/connections/callback, which finds the stored flow and
 *      passes `code` and `state` on to supervibes://connections, without exchanging anything.
 *   3. POST /api/v1/connections/{provider}/complete (bearer) takes the stored flow, checks it
 *      belongs to the same person, exchanges the code and saves the connection.
 *
 * The code is useless without the PKCE verifier (kept here) and the app's session, so passing it
 * through the sheet leaks nothing, and nobody can complete someone else's flow.
 */

const PREFIX = "app-connect:";

export async function storeAppFlow(flow: OAuthFlow): Promise<void> {
  const context = await auth.$context;
  await context.internalAdapter.createVerificationValue({
    identifier: PREFIX + flow.state,
    value: encryptJson(flow),
    expiresAt: new Date(flow.expiresAt),
  });
}

/** Whether `state` belongs to a Mac app flow still waiting to complete. Doesn't use it up. */
export async function isAppFlow(state: string): Promise<boolean> {
  const context = await auth.$context;
  const row = await context.internalAdapter.findVerificationValue(PREFIX + state);
  return Boolean(row && row.expiresAt > new Date());
}

/** The flow for `state`, removed so it can only be completed once; null if there's none or it expired. */
export async function takeAppFlow(state: string): Promise<OAuthFlow | null> {
  const context = await auth.$context;
  const row = await context.internalAdapter.consumeVerificationValue(PREFIX + state);
  if (!row) return null;
  try {
    const flow = decryptJson<OAuthFlow>(row.value);
    return flow.expiresAt > Date.now() ? flow : null;
  } catch {
    return null;
  }
}
