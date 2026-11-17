import "server-only";

import { headers } from "next/headers";
import { redirect } from "next/navigation";

import { auth, isEmailAllowed } from "@/lib/auth";

/** The signed-in session, or null. Also null if the user was removed from ALLOWED_EMAILS. */
export async function getSession() {
  const session = await auth.api.getSession({ headers: await headers() });
  if (!session || !isEmailAllowed(session.user.email)) return null;
  return session;
}

/**
 * The signed-in user, or a redirect to /sign-in.
 * Use this in every page, server action and route handler that touches user data,
 * and scope every query with `user.id`.
 */
export async function requireUser() {
  const session = await getSession();
  if (!session) redirect("/sign-in");
  return session.user;
}
