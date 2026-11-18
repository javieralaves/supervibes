import * as z from "zod";

import { PROVIDER_KEYS, type ProviderKey } from "@/lib/providers";

/* Client-safe shapes for session recaps. Generation lives in recap.ts. */

/** At most this many links to specific things in connected apps, per recap. */
export const MAX_BREADCRUMBS = 6;

/** A specific thing in a connected app that relates to a session: a meeting, commit, PR or issue. */
export type Breadcrumb = { provider: ProviderKey; title: string; url: string };

/**
 * A draft recap, stored on its block until it's posted or discarded.
 * - clear / partial / none: how much the connected apps showed about the session.
 * - no-sources: the goal has no apps to read, so the person writes it up.
 */
export type BlockRecap = {
  /** What the session was meant to be about, if anything said so. */
  planned: string | null;
  /** What looks to have happened; empty when there was nothing to go on. */
  happened: string;
  breadcrumbs: Breadcrumb[];
  found: "clear" | "partial" | "none" | "no-sources";
  /** For an intention: whether its task looks finished. */
  taskLooksDone: boolean;
  /** ISO time. */
  preparedAt: string;
};

/** A snapshot of the session a recap post covers, so it still reads right if the block is deleted. */
export type RecapSession = {
  title: string;
  startsAt: string;
  endsAt: string;
  /** What the person wanted out of the session, if they said. */
  aim?: string | null;
};

/** What the block panel sends when posting a recap. Breadcrumbs are picked by URL from the draft. */
export const postRecapSchema = z.object({
  body: z.string(),
  keep: z.array(z.url()).max(MAX_BREADCRUMBS),
  markTaskDone: z.boolean(),
});

export const breadcrumbProviderSchema = z.enum(PROVIDER_KEYS);
