import * as z from "zod";

/* Client-safe settings shape, defaults and validation. Storage lives in settings.ts. */

export const CLOCKS = ["12h", "24h"] as const;
export type Clock = (typeof CLOCKS)[number];

export type Settings = {
  /** Bedtime, minutes after local midnight. */
  sleepStart: number;
  /** Wake-up time, minutes after local midnight. */
  wakeTime: number;
  /** null follows the device. */
  clock: Clock | null;
};

export const DEFAULT_SETTINGS: Settings = { sleepStart: 23 * 60, wakeTime: 7 * 60, clock: null };

/** Times are picked in 15-minute steps. */
export const TIME_STEP = 15;

const minuteOfDay = z
  .number()
  .int()
  .min(0)
  .max(24 * 60 - TIME_STEP)
  .refine((m) => m % TIME_STEP === 0, "Pick a time on the quarter hour.");

export const settingsSchema = z
  .object({
    sleepStart: minuteOfDay,
    wakeTime: minuteOfDay,
    clock: z.enum(CLOCKS).nullable(),
  })
  .refine((s) => s.sleepStart !== s.wakeTime, "Bedtime and wake-up time can't be the same.");

/** Minutes awake per day for a sleep schedule. */
export function awakeMinutes({ sleepStart, wakeTime }: Pick<Settings, "sleepStart" | "wakeTime">) {
  return (sleepStart - wakeTime + 24 * 60) % (24 * 60);
}

/** A time zone the runtime knows, e.g. "Europe/Madrid", as a browser reports it. */
export const timeZoneSchema = z
  .string()
  .min(1)
  .max(64)
  .refine((tz) => {
    try {
      new Intl.DateTimeFormat("en", { timeZone: tz });
      return true;
    } catch {
      return false;
    }
  }, "Unknown time zone.");
