import { addDays } from "@/lib/target-date";

/*
 * The instants a calendar day starts and ends in a given time zone, so the server can ask
 * "what's on today" in the person's own zone rather than the server's.
 */

/** How far `timeZone` is ahead of UTC at instant `at`, in milliseconds. */
function offsetAt(at: number, timeZone: string): number {
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone,
    hourCycle: "h23",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
  }).formatToParts(new Date(at));
  const get = (type: Intl.DateTimeFormatPartTypes) => Number(parts.find((p) => p.type === type)?.value);
  const wallClockAsUTC = Date.UTC(get("year"), get("month") - 1, get("day"), get("hour"), get("minute"), get("second"));
  return wallClockAsUTC - Math.floor(at / 1000) * 1000;
}

/** The instant local midnight starts `day` ("YYYY-MM-DD") in `timeZone`. */
export function startOfDayIn(day: string, timeZone: string): Date {
  const [y, m, d] = day.split("-").map(Number);
  const midnightUTC = Date.UTC(y, m - 1, d);
  // Two passes, so a DST change between UTC midnight and local midnight still lands right.
  const first = midnightUTC - offsetAt(midnightUTC, timeZone);
  return new Date(midnightUTC - offsetAt(first, timeZone));
}

/** [start, end) of `day` in `timeZone`. Days around DST changes are 23 or 25 hours long. */
export function dayBoundsIn(day: string, timeZone: string): { start: Date; end: Date } {
  return { start: startOfDayIn(day, timeZone), end: startOfDayIn(addDays(day, 1), timeZone) };
}
