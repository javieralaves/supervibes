import "server-only";

import { createRoute, OpenAPIHono, z } from "@hono/zod-openapi";

import { storeAppFlow, takeAppFlow } from "@/lib/app-connect";
import type { ApiEnv } from "@/lib/api/auth";
import { apiError, ErrorSchema, errorResponses } from "@/lib/api/errors";
import { deleteConnection, listConnections, saveConnection } from "@/lib/connections";
import {
  beginAuthorization,
  completeAuthorization,
  isProviderConfigured,
  listReadTools,
  ProviderNotConfiguredError,
} from "@/lib/mcp-oauth";
import { PROVIDER_KEYS, PROVIDERS } from "@/lib/providers";

const ProviderSchema = z.enum(PROVIDER_KEYS).openapi("Provider");

const ConnectionSchema = z
  .object({
    provider: ProviderSchema,
    label: z.string().openapi({ example: "Linear" }),
    description: z.string().openapi({ example: "Issues, projects and cycles." }),
    configured: z.boolean().openapi({ description: "false until the server has this app's credentials." }),
    connection: z
      .object({
        status: z.enum(["connected", "error"]),
        lastError: z.string().nullable(),
        connectedAt: z.iso.datetime(),
      })
      .nullable()
      .openapi({ description: "null when not connected." }),
  })
  .openapi("Connection");

const ConnectionsSchema = z.object({ connections: z.array(ConnectionSchema) }).openapi("Connections");

const providerParam = z.object({ provider: ProviderSchema.openapi({ param: { name: "provider", in: "path" } }) });

const notFound = { description: "Not found.", content: { "application/json": { schema: ErrorSchema } } };

const listRoute = createRoute({
  method: "get",
  path: "/connections",
  operationId: "listConnections",
  summary: "Every app Supervibes can read from, and whether it's connected",
  security: [{ bearerAuth: [] }],
  responses: {
    200: { description: "OK", content: { "application/json": { schema: ConnectionsSchema } } },
    401: errorResponses[401],
  },
});

const startRoute = createRoute({
  method: "post",
  path: "/connections/{provider}/start",
  operationId: "startConnection",
  summary: "Begin connecting an app: open `authorizationUrl` in the system sign-in sheet",
  description:
    "The provider sends the sheet back to supervibes://connections with `state` and `code` (or `error`); pass them to complete.",
  security: [{ bearerAuth: [] }],
  request: { params: providerParam },
  responses: {
    200: {
      description: "OK",
      content: { "application/json": { schema: z.object({ authorizationUrl: z.url(), state: z.string() }).openapi("ConnectionStart") } },
    },
    ...errorResponses,
  },
});

const completeRoute = createRoute({
  method: "post",
  path: "/connections/{provider}/complete",
  operationId: "completeConnection",
  summary: "Finish connecting an app with the code the sign-in sheet came back with",
  security: [{ bearerAuth: [] }],
  request: {
    params: providerParam,
    body: {
      required: true,
      content: { "application/json": { schema: z.object({ state: z.string(), code: z.string() }).openapi("ConnectionComplete") } },
    },
  },
  responses: {
    200: { description: "Connected", content: { "application/json": { schema: ConnectionSchema } } },
    ...errorResponses,
  },
});

const deleteRoute = createRoute({
  method: "delete",
  path: "/connections/{provider}",
  operationId: "disconnect",
  summary: "Disconnect an app. Goal sources that use it are removed.",
  security: [{ bearerAuth: [] }],
  request: { params: providerParam },
  responses: {
    204: { description: "Disconnected" },
    401: errorResponses[401],
    404: notFound,
  },
});

async function connectionsFor(userId: string) {
  const connected = new Map((await listConnections(userId)).map((c) => [c.provider, c]));
  return PROVIDER_KEYS.map((provider) => {
    const connection = connected.get(provider);
    return {
      provider,
      label: PROVIDERS[provider].label,
      description: PROVIDERS[provider].description,
      configured: isProviderConfigured(provider),
      connection: connection
        ? {
            status: connection.status === "error" ? ("error" as const) : ("connected" as const),
            lastError: connection.lastError,
            connectedAt: connection.createdAt.toISOString(),
          }
        : null,
    };
  });
}

export const connections = new OpenAPIHono<ApiEnv>()
  .openapi(listRoute, async (c) => c.json({ connections: await connectionsFor(c.var.user.id) }, 200))
  .openapi(startRoute, async (c) => {
    const { provider } = c.req.valid("param");
    try {
      const { authorizationUrl, flow } = await beginAuthorization(provider, c.var.user.id);
      await storeAppFlow(flow);
      return c.json({ authorizationUrl: authorizationUrl.toString(), state: flow.state }, 200);
    } catch (error) {
      if (error instanceof ProviderNotConfiguredError) {
        return c.json(apiError("not_configured", "This app needs a one-time setup before it can connect."), 400);
      }
      console.error(`[connections] app start ${provider} failed`, error);
      return c.json(apiError("start_failed", "Couldn’t reach that app’s sign-in. Try again in a moment."), 400);
    }
  })
  .openapi(completeRoute, async (c) => {
    const { provider } = c.req.valid("param");
    const { state, code } = c.req.valid("json");
    const userId = c.var.user.id;

    const flow = await takeAppFlow(state);
    // Same person, same app, still fresh: otherwise someone else's or a stale sign-in.
    if (!flow || flow.userId !== userId || flow.provider !== provider) {
      return c.json(apiError("expired", "That sign-in took too long or came from another session. Try connecting again."), 400);
    }

    try {
      const tokens = await completeAuthorization(flow, code);
      const readTools = await listReadTools(provider, tokens.access_token);
      await saveConnection(userId, provider, PROVIDERS[provider].serverUrl, flow.clientInfo, tokens, readTools);
    } catch (error) {
      console.error(`[connections] app complete ${provider} failed`, error);
      return c.json(apiError("failed", "The app didn’t finish connecting. Try again in a moment."), 400);
    }

    const saved = (await connectionsFor(userId)).find((item) => item.provider === provider)!;
    return c.json(saved, 200);
  })
  .openapi(deleteRoute, async (c) => {
    const { provider } = c.req.valid("param");
    const existing = (await listConnections(c.var.user.id)).some((item) => item.provider === provider);
    if (!existing) return c.json(apiError("not_found", "That app isn’t connected."), 404);
    await deleteConnection(c.var.user.id, provider);
    return c.body(null, 204);
  });
