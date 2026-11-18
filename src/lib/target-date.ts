/*
 * A goal's target date is a calendar day ("YYYY-MM-DD") with no time zone.
 * Pure and client-safe. "Today" is the local day wherever this runs, so on the
 * server it can be a day off from the person's own; fine for "in 3 weeks".
 */

/** Today's local calendar day as "YYYY-MM-DD". */
export function todayISO(now = new Date()): string {
  const y = now.getFullYear();
  const m = String(now.getMonth() + 1).padStart(2, "0");
  const d = String(now.getDate()).padStart(2, "0");
  return `${y}-${m}-${d}`;
}

function utcDay(iso: string): number {
  const [y, m, d] = iso.split("-").map(Number);
  return Date.UTC(y, m - 1, d);
}

/** Whole days from `today` to `target`; negative once it has passed. */
export function daysUntil(target: string, today = todayISO()): number {
  return Math.round((utcDay(target) - utcDay(today)) / 86_400_000);
}

/** "Mar 31", or "Mar 31, 2027" when it isn't this year. */
export function formatTargetDate(target: string, today = todayISO()): string {
  const sameYear = target.slice(0, 4) === today.slice(0, 4);
  return new Date(utcDay(target)).toLocaleDateString("en-US", {
    month: "short",
    day: "numeric",
    year: sameYear ? undefined : "numeric",
    timeZone: "UTC",
  });
}

function span(days: number): string {
  if (days < 14) return `${days} day${days === 1 ? "" : "s"}`;
  if (days < 60) return `${Math.round(days / 7)} weeks`;
  const months = Math.round(days / 30.44);
  return months < 24 ? `${months} months` : `${Math.round(days / 365.25)} years`;
}

/** "today", "tomorrow", "in 3 weeks", "2 days past". */
export function relativeTarget(days: number): string {
  if (days === 0) return "today";
  if (days === 1) return "tomorrow";
  if (days === -1) return "yesterday";
  return days > 0 ? `in ${span(days)}` : `${span(-days)} past`;
}

/** For a prompt, e.g. "2027-03-31, 133 days away (today is 2026-11-18)". */
export function targetDateForPrompt(target: string, today = todayISO()): string {
  const days = daysUntil(target, today);
  const distance =
    days === 0 ? "which is today" : days > 0 ? `${days} days away` : `${-days} days ago, so it has passed`;
  return `${target}, ${distance} (today is ${today})`;
}
