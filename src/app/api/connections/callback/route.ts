import { cookies } from "next/headers";
import { NextResponse } from "next/server";

import { isAppFlow } from "@/lib/app-connect";
import { saveConnection } from "@/lib/connections";
import { decryptJson } from "@/lib/crypto";
import { completeAuthorization, FLOW_COOKIE, listReadTools, type OAuthFlow } from "@/lib/mcp-oauth";
import { PROVIDERS } from "@/lib/providers";
import { requireUser } from "@/lib/session";

export async function GET(request: Request) {
  const url = new URL(request.url);

  // Started by the Mac app (see lib/app-connect.ts): hand the result back to the app, which
  // completes it with its own session. The browser here isn't signed in to Supervibes.
  const state = url.searchParams.get("state");
  if (state && (await isAppFlow(state))) {
    const back = new URL("supervibes://connections");
    back.searchParams.set("state", state);
    const code = url.searchParams.get("code");
    const denied = url.searchParams.get("error");
    if (code && !denied) back.searchParams.set("code", code);
    else back.searchParams.set("error", denied === "access_denied" ? "denied" : "failed");
    return new Response(null, { status: 302, headers: { Location: back.toString(), "Cache-Control": "no-store" } });
  }

  const user = await requireUser();
  const jar = await cookies();
  const raw = jar.get(FLOW_COOKIE)?.value;
  jar.delete({ name: FLOW_COOKIE, path: "/api/connections/callback" });

  const back = (query: string) => NextResponse.redirect(new URL(`/connections?${query}`, request.url));

  let flow: OAuthFlow;
  try {
    if (!raw) throw new Error("missing flow");
    flow = decryptJson<OAuthFlow>(raw);
  } catch {
    return back("error=expired");
  }

  // The flow must belong to this user, be recent, and match the state we sent.
  if (flow.userId !== user.id || flow.expiresAt < Date.now() || url.searchParams.get("state") !== flow.state) {
    return back("error=expired");
  }

  const denied = url.searchParams.get("error");
  const code = url.searchParams.get("code");
  if (denied || !code) return back(`error=${denied === "access_denied" ? "denied" : "failed"}`);

  try {
    const tokens = await completeAuthorization(flow, code);
    const readTools = await listReadTools(flow.provider, tokens.access_token);
    await saveConnection(user.id, flow.provider, PROVIDERS[flow.provider].serverUrl, flow.clientInfo, tokens, readTools);
    return back(`connected=${flow.provider}`);
  } catch (error) {
    console.error(`[connections] callback ${flow.provider} failed`, error);
    return back("error=failed");
  }
}
