"use server";

import { refresh } from "next/cache";

import { requireUser } from "@/lib/session";
import { saveSettings } from "@/lib/settings";
import { settingsSchema } from "@/lib/settings-schema";

export type SaveResult = { ok: true } | { ok: false; error: string };

export async function saveSettingsAction(input: unknown): Promise<SaveResult> {
  const user = await requireUser();
  const parsed = settingsSchema.safeParse(input);
  if (!parsed.success) return { ok: false, error: parsed.error.issues[0]?.message ?? "Check your settings." };
  await saveSettings(user.id, parsed.data);
  refresh();
  return { ok: true };
}
