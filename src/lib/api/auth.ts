import "server-only";

import { createMiddleware } from "hono/factory";

import { apiError } from "@/lib/api/errors";
import { auth, isEmailAllowed, type Session } from "@/lib/auth";

export type ApiEnv = { Variables: { user: Session["user"] } };

/**
 * The API's version of requireUser(): the session comes from `Authorization: Bearer …` (the Mac
 * app) or the session cookie, and a missing or ended session is a 401 rather than a redirect.
 * Same ALLOWED_EMAILS rule as the web app. Scope every query with `c.var.user.id`.
 */
export const requireApiUser = createMiddleware<ApiEnv>(async (c, next) => {
  const session = await auth.api.getSession({ headers: c.req.raw.headers });
  if (!session || !isEmailAllowed(session.user.email)) {
    return c.json(apiError("unauthorized", "Sign in again."), 401);
  }
  c.set("user", session.user);
  await next();
});
