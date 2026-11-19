import "server-only";

import { eq } from "drizzle-orm";

import { db } from "@/db";
import { userSettings } from "@/db/schema";
import { DEFAULT_SETTINGS, type Clock, type Settings } from "@/lib/settings-schema";

/** The user's settings, or the defaults for anything they haven't set. */
export async function getSettings(userId: string): Promise<Settings> {
  const [row] = await db
    .select({ sleepStart: userSettings.sleepStart, wakeTime: userSettings.wakeTime, clock: userSettings.clock })
    .from(userSettings)
    .where(eq(userSettings.userId, userId));
  if (!row) return DEFAULT_SETTINGS;
  return { ...row, clock: row.clock === "12h" || row.clock === "24h" ? (row.clock as Clock) : null };
}

export async function saveSettings(userId: string, settings: Settings): Promise<void> {
  await db
    .insert(userSettings)
    .values({ userId, ...settings })
    .onConflictDoUpdate({ target: userSettings.userId, set: settings });
}

/** The person's time zone, as their browser last reported it; null until it has. */
export async function getTimeZone(userId: string): Promise<string | null> {
  const [row] = await db
    .select({ timeZone: userSettings.timeZone })
    .from(userSettings)
    .where(eq(userSettings.userId, userId));
  return row?.timeZone ?? null;
}
