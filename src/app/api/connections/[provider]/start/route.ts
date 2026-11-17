import { cookies } from "next/headers";
import { NextResponse } from "next/server";

import { encryptJson } from "@/lib/crypto";
import { beginAuthorization, FLOW_COOKIE, ProviderNotConfiguredError } from "@/lib/mcp-oauth";
import { isProvider } from "@/lib/providers";
import { requireUser } from "@/lib/session";

export async function GET(request: Request, ctx: RouteContext<"/api/connections/[provider]/start">) {
  const user = await requireUser();
  const { provider } = await ctx.params;
  const back = (error: string) =>
    NextResponse.redirect(new URL(`/connections?error=${encodeURIComponent(error)}`, request.url));

  if (!isProvider(provider)) return back("unknown_app");

  try {
    const { authorizationUrl, flow } = await beginAuthorization(provider, user.id);
    (await cookies()).set(FLOW_COOKIE, encryptJson(flow), {
      httpOnly: true,
      secure: process.env.NODE_ENV === "production",
      sameSite: "lax",
      path: "/api/connections/callback",
      maxAge: 10 * 60,
    });
    return NextResponse.redirect(authorizationUrl);
  } catch (error) {
    if (error instanceof ProviderNotConfiguredError) return back("not_configured");
    console.error(`[connections] start ${provider} failed`, error);
    return back("start_failed");
  }
}
