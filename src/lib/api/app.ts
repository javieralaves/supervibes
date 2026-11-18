import "server-only";

import { OpenAPIHono } from "@hono/zod-openapi";

import { requireApiUser, type ApiEnv } from "@/lib/api/auth";
import { apiError } from "@/lib/api/errors";
import { me } from "@/lib/api/routes/me";
import { today } from "@/lib/api/routes/today";

/*
 * The Supervibes API, served at /api/v1 (see app/api/v1/[[...route]]/route.ts).
 *
 * Each route is declared once with createRoute: its path, input and output schemas. That one
 * declaration validates requests, types the handler, and produces the OpenAPI document the Mac
 * app's client is generated from (`npm run api:spec`). Handlers call the same src/lib functions
 * the web app's server actions do.
 */

export const api = new OpenAPIHono<ApiEnv>({
  // Request validation failures get the standard error shape.
  defaultHook: (result, c) => {
    if (!result.success) {
      const message = result.error.issues[0]?.message ?? "Check the request.";
      return c.json(apiError("invalid_request", message), 400);
    }
  },
}).basePath("/api/v1");

api.openAPIRegistry.registerComponent("securitySchemes", "bearerAuth", {
  type: "http",
  scheme: "bearer",
  description: "The session token from the Mac app's sign-in (see lib/native-auth.ts).",
});

// The spec is only served in development, for `npm run api:spec`.
if (process.env.NODE_ENV !== "production") {
  api.doc("/openapi.json", {
    openapi: "3.0.3",
    info: { title: "Supervibes", version: "1.0.0" },
  });
}

api.use("/*", async (c, next) => {
  if (c.req.path === "/api/v1/openapi.json") return next();
  return requireApiUser(c, next);
});

api.route("/", me);
api.route("/", today);

api.notFound((c) => c.json(apiError("not_found", "There's nothing here."), 404));

api.onError((error, c) => {
  console.error(`[api] ${c.req.method} ${c.req.path} failed`, error);
  return c.json(apiError("internal", "Something went wrong. Try again."), 500);
});
