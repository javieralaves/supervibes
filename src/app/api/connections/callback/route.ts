import { isAppFlow } from "@/lib/app-connect";

/**
 * Where a connected app's sign-in comes back to. Connections are started by the Mac app (see
 * lib/app-connect.ts): this hands the result back to it, and the app completes the connection with
 * its own session. The browser here isn't signed in to Supervibes.
 */
export async function GET(request: Request) {
  const url = new URL(request.url);
  const state = url.searchParams.get("state");
  if (!state || !(await isAppFlow(state))) {
    return new Response("This link has expired. Connect the app again from Supervibes on your Mac.", {
      status: 400,
      headers: { "Content-Type": "text/plain; charset=utf-8", "Cache-Control": "no-store" },
    });
  }

  const back = new URL("supervibes://connections");
  back.searchParams.set("state", state);
  const code = url.searchParams.get("code");
  const denied = url.searchParams.get("error");
  if (code && !denied) back.searchParams.set("code", code);
  else back.searchParams.set("error", denied === "access_denied" ? "denied" : "failed");
  return new Response(null, { status: 302, headers: { Location: back.toString(), "Cache-Control": "no-store" } });
}
