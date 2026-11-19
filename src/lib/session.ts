import "server-only";

import { headers } from "next/headers";
import { cache } from "react";

import { auth, isEmailAllowed } from "@/lib/auth";

/**
 * The signed-in session, or null. Also null if the user was removed from ALLOWED_EMAILS.
 * Cached per request, so several components can call it without extra lookups.
 */
export const getSession = cache(async () => {
  const session = await auth.api.getSession({ headers: await headers() });
  if (!session || !isEmailAllowed(session.user.email)) return null;
  return session;
});
