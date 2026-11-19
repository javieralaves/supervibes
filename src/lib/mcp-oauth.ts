import "server-only";

import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import {
  discoverOAuthServerInfo,
  exchangeAuthorization,
  refreshAuthorization,
  registerClient,
  startAuthorization,
} from "@modelcontextprotocol/sdk/client/auth.js";
import { StreamableHTTPClientTransport } from "@modelcontextprotocol/sdk/client/streamableHttp.js";
import type { OAuthClientInformationMixed, OAuthTokens } from "@modelcontextprotocol/sdk/shared/auth.js";

import { PROVIDERS, type ProviderKey } from "@/lib/providers";

/** Tokens as stored: the OAuth response plus an absolute expiry. */
export type StoredTokens = OAuthTokens & { expires_at?: number };

/** Short-lived state carried through the browser redirect in an encrypted cookie. */
export type OAuthFlow = {
  state: string;
  userId: string;
  provider: ProviderKey;
  codeVerifier: string;
  clientInfo: OAuthClientInformationMixed;
  expiresAt: number;
};

export function redirectUrl(): string {
  const base = process.env.BETTER_AUTH_URL;
  if (!base) throw new Error("BETTER_AUTH_URL is not set.");
  return new URL("/api/connections/callback", base).toString();
}

/** RFC 8707 resource indicator. GitHub's OAuth server isn't an MCP-aware server, so skip it there. */
function resourceFor(provider: ProviderKey, discovered?: string): string | undefined {
  return PROVIDERS[provider].registration === "dynamic" ? discovered : undefined;
}

export class ProviderNotConfiguredError extends Error {}

export function isProviderConfigured(provider: ProviderKey): boolean {
  if (PROVIDERS[provider].registration === "dynamic") return true;
  return Boolean(process.env.GITHUB_CLIENT_ID && process.env.GITHUB_CLIENT_SECRET);
}

async function clientInfoFor(
  provider: ProviderKey,
  authorizationServerUrl: string,
  metadata: Awaited<ReturnType<typeof discoverOAuthServerInfo>>["authorizationServerMetadata"],
): Promise<OAuthClientInformationMixed> {
  const config = PROVIDERS[provider];

  if (config.registration === "static") {
    const clientId = process.env.GITHUB_CLIENT_ID;
    const clientSecret = process.env.GITHUB_CLIENT_SECRET;
    if (!clientId || !clientSecret) throw new ProviderNotConfiguredError();
    return { client_id: clientId, client_secret: clientSecret, token_endpoint_auth_method: "client_secret_post" };
  }

  // Dynamic client registration (RFC 7591): a public client protected by PKCE.
  return registerClient(authorizationServerUrl, {
    metadata,
    scope: config.oauthScope,
    clientMetadata: {
      client_name: "Supervibes",
      redirect_uris: [redirectUrl()],
      grant_types: ["authorization_code", "refresh_token"],
      response_types: ["code"],
      token_endpoint_auth_method: "none",
    },
  });
}

/** Step 1: discover the provider's OAuth server, register if needed, and build the consent URL. */
export async function beginAuthorization(provider: ProviderKey, userId: string) {
  const config = PROVIDERS[provider];
  const info = await discoverOAuthServerInfo(config.serverUrl);
  const clientInfo = await clientInfoFor(provider, info.authorizationServerUrl, info.authorizationServerMetadata);
  const state = crypto.randomUUID();

  const { authorizationUrl, codeVerifier } = await startAuthorization(info.authorizationServerUrl, {
    metadata: info.authorizationServerMetadata,
    clientInformation: clientInfo,
    redirectUrl: redirectUrl(),
    scope: config.oauthScope,
    state,
    resource: resourceFor(provider, info.resourceMetadata?.resource),
  });

  const flow: OAuthFlow = {
    state,
    userId,
    provider,
    codeVerifier,
    clientInfo,
    expiresAt: Date.now() + 10 * 60 * 1000,
  };
  return { authorizationUrl, flow };
}

function withExpiry(tokens: OAuthTokens): StoredTokens {
  return tokens.expires_in ? { ...tokens, expires_at: Date.now() + tokens.expires_in * 1000 } : tokens;
}

/** Step 2: exchange the code from the callback for tokens. */
export async function completeAuthorization(flow: OAuthFlow, code: string): Promise<StoredTokens> {
  const config = PROVIDERS[flow.provider];
  const info = await discoverOAuthServerInfo(config.serverUrl);
  const tokens = await exchangeAuthorization(info.authorizationServerUrl, {
    metadata: info.authorizationServerMetadata,
    clientInformation: flow.clientInfo,
    authorizationCode: code,
    codeVerifier: flow.codeVerifier,
    redirectUri: redirectUrl(),
    resource: resourceFor(flow.provider, info.resourceMetadata?.resource),
  });
  return withExpiry(tokens);
}

/** Refreshes tokens if they expire within a minute. Returns null when no refresh was needed. */
export async function refreshIfNeeded(
  provider: ProviderKey,
  clientInfo: OAuthClientInformationMixed,
  tokens: StoredTokens,
): Promise<StoredTokens | null> {
  if (!tokens.expires_at || tokens.expires_at - Date.now() > 60_000) return null;
  if (!tokens.refresh_token) throw new Error("The connection expired. Reconnect it.");

  const info = await discoverOAuthServerInfo(PROVIDERS[provider].serverUrl);
  const refreshed = await refreshAuthorization(info.authorizationServerUrl, {
    metadata: info.authorizationServerMetadata,
    clientInformation: clientInfo,
    refreshToken: tokens.refresh_token,
    resource: resourceFor(provider, info.resourceMetadata?.resource),
  });
  return withExpiry(refreshed);
}

const READ_NAME = /^(get|list|search|read|fetch|query|find|lookup|retrieve)[_-]/i;

/**
 * Connects to the MCP server and returns the names of its read-only tools:
 * those annotated readOnlyHint, or (when unannotated) named like reads.
 * Syncs may only call these.
 */
export async function listReadTools(provider: ProviderKey, accessToken: string): Promise<string[]> {
  const transport = new StreamableHTTPClientTransport(new URL(PROVIDERS[provider].serverUrl), {
    requestInit: { headers: { Authorization: `Bearer ${accessToken}` } },
  });
  const client = new Client({ name: "supervibes", version: "1.0.0" });
  await client.connect(transport);
  try {
    const names: string[] = [];
    let cursor: string | undefined;
    do {
      const page = await client.listTools(cursor ? { cursor } : {});
      for (const tool of page.tools) {
        const a = tool.annotations;
        const readOnly = a?.readOnlyHint === true || (a?.readOnlyHint === undefined && !a?.destructiveHint && READ_NAME.test(tool.name));
        if (readOnly) names.push(tool.name);
      }
      cursor = page.nextCursor;
    } while (cursor);
    return names;
  } finally {
    await client.close();
  }
}
