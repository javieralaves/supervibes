import "server-only";

import type { OAuthClientInformationMixed } from "@modelcontextprotocol/sdk/shared/auth.js";
import { and, eq } from "drizzle-orm";

import { db } from "@/db";
import { connections } from "@/db/schema";
import { decryptJson, encryptJson } from "@/lib/crypto";
import { refreshIfNeeded, type StoredTokens } from "@/lib/mcp-oauth";
import { isProvider, type ProviderKey } from "@/lib/providers";

/** What the UI may see about a connection: never tokens or client secrets. */
export type ConnectionDTO = {
  id: string;
  provider: ProviderKey;
  status: string;
  lastError: string | null;
  readToolCount: number;
  createdAt: Date;
};

export async function listConnections(userId: string): Promise<ConnectionDTO[]> {
  const rows = await db
    .select({
      id: connections.id,
      provider: connections.provider,
      status: connections.status,
      lastError: connections.lastError,
      readTools: connections.readTools,
      createdAt: connections.createdAt,
    })
    .from(connections)
    .where(eq(connections.userId, userId));

  return rows
    .filter((r): r is typeof r & { provider: ProviderKey } => isProvider(r.provider))
    .map(({ readTools, ...r }) => ({ ...r, readToolCount: readTools.length }));
}

export async function saveConnection(
  userId: string,
  provider: ProviderKey,
  serverUrl: string,
  clientInfo: OAuthClientInformationMixed,
  tokens: StoredTokens,
  readTools: string[],
) {
  const values = {
    serverUrl,
    clientInfo: encryptJson(clientInfo),
    tokens: encryptJson(tokens),
    readTools,
    status: "connected",
    lastError: null,
  };
  await db
    .insert(connections)
    .values({ userId, provider, ...values })
    .onConflictDoUpdate({ target: [connections.userId, connections.provider], set: values });
}

export async function deleteConnection(userId: string, provider: ProviderKey): Promise<void> {
  await db.delete(connections).where(and(eq(connections.userId, userId), eq(connections.provider, provider)));
}

export async function markConnectionError(userId: string, connectionId: string, message: string) {
  await db
    .update(connections)
    .set({ status: "error", lastError: message })
    .where(and(eq(connections.id, connectionId), eq(connections.userId, userId)));
}

/**
 * Server-only: a connection with a fresh access token, refreshing and saving
 * new tokens if they're about to expire. Null if it isn't this user's.
 */
export async function getUsableConnection(userId: string, connectionId: string) {
  const [row] = await db
    .select()
    .from(connections)
    .where(and(eq(connections.id, connectionId), eq(connections.userId, userId)));
  if (!row || !isProvider(row.provider)) return null;

  const clientInfo = decryptJson<OAuthClientInformationMixed>(row.clientInfo);
  let tokens = decryptJson<StoredTokens>(row.tokens);

  const refreshed = await refreshIfNeeded(row.provider, clientInfo, tokens);
  if (refreshed) {
    tokens = refreshed;
    await db
      .update(connections)
      .set({ tokens: encryptJson(tokens), status: "connected", lastError: null })
      .where(eq(connections.id, row.id));
  }

  return {
    id: row.id,
    provider: row.provider,
    serverUrl: row.serverUrl,
    readTools: row.readTools,
    accessToken: tokens.access_token,
  };
}
