import { useSyncExternalStore } from "react";

import type { Clock } from "@/lib/settings-schema";

/*
 * Formats minutes-after-midnight in the user's chosen clock. Done by hand, not
 * with Intl, so server and browser always print the same thing.
 */

function parts(minutes: number) {
  const m = ((Math.round(minutes) % 1440) + 1440) % 1440;
  return { h: Math.floor(m / 60), min: m % 60 };
}

const pad = (n: number) => String(n).padStart(2, "0");
const h12 = (h: number) => (h % 12 === 0 ? 12 : h % 12);
const period = (h: number) => (h < 12 ? "AM" : "PM");

/** "14:30" or "2:30 PM". */
export function formatTime(minutes: number, clock: Clock) {
  const { h, min } = parts(minutes);
  return clock === "24h" ? `${pad(h)}:${pad(min)}` : `${h12(h)}:${pad(min)} ${period(h)}`;
}

/** Hour-row label: "14:00" or "2 PM". */
export function formatHour(hour: number, clock: Clock) {
  const h = ((hour % 24) + 24) % 24;
  return clock === "24h" ? `${pad(h)}:00` : `${h12(h)} ${period(h)}`;
}

/** "14:30–15:30", "2:30–3:30 PM" or "11:30 AM–12:30 PM". */
export function formatRange(start: number, end: number, clock: Clock) {
  if (clock === "24h") return `${formatTime(start, clock)}–${formatTime(end, clock)}`;
  const a = parts(start);
  const b = parts(end);
  const startText = period(a.h) === period(b.h) ? `${h12(a.h)}:${pad(a.min)}` : formatTime(start, clock);
  return `${startText}–${formatTime(end, clock)}`;
}

/* The device's own preference, read in the browser only (the server can't know it). */
function deviceClock(): Clock {
  const cycle = new Intl.DateTimeFormat(undefined, { hour: "numeric" }).resolvedOptions().hourCycle;
  return cycle === "h11" || cycle === "h12" ? "12h" : "24h";
}
const noop = () => () => {};
const serverClock = (): Clock => "24h";

/** The clock to show: the user's choice, or their device's until they pick one. */
export function useClock(preference: Clock | null): Clock {
  const device = useSyncExternalStore(noop, deviceClock, serverClock);
  return preference ?? device;
}
