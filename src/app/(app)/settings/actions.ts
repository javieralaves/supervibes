"use server";

import { refresh } from "next/cache";

import { requireUser } from "@/lib/session";
import { saveSettings, saveTimeZone } from "@/lib/settings";
import { settingsSchema, timeZoneSchema } from "@/lib/settings-schema";

export type SaveResult = { ok: true } | { ok: false; error: string };

export async function saveSettingsAction(input: unknown): Promise<SaveResult> {
  const user = await requireUser();
  const parsed = settingsSchema.safeParse(input);
  if (!parsed.success) return { ok: false, error: parsed.error.issues[0]?.message ?? "Check your settings." };
  await saveSettings(user.id, parsed.data);
  refresh();
  return { ok: true };
}

/** Records the time zone the browser reports, when it differs from the one stored. Nothing on screen changes. */
export async function syncTimeZoneAction(timeZone: unknown): Promise<SaveResult> {
  const user = await requireUser();
  const parsed = timeZoneSchema.safeParse(timeZone);
  if (!parsed.success) return { ok: false, error: "Unknown time zone." };
  await saveTimeZone(user.id, parsed.data);
  return { ok: true };
}
