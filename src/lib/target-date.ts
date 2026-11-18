/*
 * Calendar days ("YYYY-MM-DD") with no time zone: a goal's target date, and a
 * task's planned day and due date. Pure and client-safe. "Today" is the local
 * day wherever this runs, so on the server it can be a day off from the
 * person's own; pass their time zone to `todayIn` where that matters.
 */

/** Today's local calendar day as "YYYY-MM-DD". */
export function todayISO(now = new Date()): string {
  const y = now.getFullYear();
  const m = String(now.getMonth() + 1).padStart(2, "0");
  const d = String(now.getDate()).padStart(2, "0");
  return `${y}-${m}-${d}`;
}

/**
 * Today's calendar day in a time zone, as "YYYY-MM-DD". Falls back to the local
 * day wherever this runs when the zone is missing or unknown.
 */
export function todayIn(timeZone: string | null | undefined, now = new Date()): string {
  if (!timeZone) return todayISO(now);
  try {
    // en-CA formats as YYYY-MM-DD.
    return new Intl.DateTimeFormat("en-CA", { timeZone, year: "numeric", month: "2-digit", day: "2-digit" }).format(now);
  } catch {
    return todayISO(now);
  }
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

/** The calendar day `n` days after `day` (before, when negative). */
export function addDays(day: string, n: number): string {
  return new Date(utcDay(day) + n * 86_400_000).toISOString().slice(0, 10);
}

/** "Friday" or "Fri" for a calendar day. */
export function weekdayName(day: string, style: "long" | "short" = "short"): string {
  return new Date(utcDay(day)).toLocaleDateString("en-US", { weekday: style, timeZone: "UTC" });
}

/** "Today", "Tomorrow", "Yesterday", "Fri" within a week either way, otherwise "Nov 28". */
export function relativeDayLabel(day: string, today = todayISO()): string {
  const days = daysUntil(day, today);
  if (days === 0) return "Today";
  if (days === 1) return "Tomorrow";
  if (days === -1) return "Yesterday";
  if (Math.abs(days) < 7) return weekdayName(day);
  return formatTargetDate(day, today);
}

const dayCount = (n: number) => `${n} day${n === 1 ? "" : "s"}`;

/**
 * A task's planned day and due date for a prompt, measured from `today`, e.g.
 * "planned for 2026-11-20 (in 2 days); due 2026-11-24 (in 6 days)". A finished
 * task only says when it was due. Empty when it has neither.
 */
export function taskDaysForPrompt(
  t: { plannedFor: string | null; dueOn: string | null },
  today: string,
  { done = false }: { done?: boolean } = {},
): string {
  const parts: string[] = [];
  if (t.plannedFor && !done) {
    const d = daysUntil(t.plannedFor, today);
    const when = d === 0 ? "today" : d > 0 ? `in ${dayCount(d)}` : `${dayCount(-d)} ago and still not done, so it slipped`;
    parts.push(`planned for ${t.plannedFor} (${when})`);
  }
  if (t.dueOn) {
    if (done) {
      parts.push(`was due ${t.dueOn}`);
    } else {
      const d = daysUntil(t.dueOn, today);
      parts.push(`due ${t.dueOn} (${d === 0 ? "today" : d > 0 ? `in ${dayCount(d)}` : `${dayCount(-d)} overdue`})`);
    }
  }
  return parts.join("; ");
}

/** The Monday that starts the week `day` falls in, "YYYY-MM-DD". Weeks run Monday to Sunday. */
export function weekStartOf(day: string): string {
  // getUTCDay: 0 is Sunday; step back to Monday.
  const weekday = new Date(utcDay(day)).getUTCDay();
  return addDays(day, -((weekday + 6) % 7));
}

/** "Nov 16–22", or "Nov 30 – Dec 6" across months, for the week starting `weekStart`. */
export function formatWeek(weekStart: string): string {
  const end = addDays(weekStart, 6);
  const month = (d: string) => new Date(utcDay(d)).toLocaleDateString("en-US", { month: "short", timeZone: "UTC" });
  const day = (d: string) => Number(d.slice(8, 10));
  return month(weekStart) === month(end)
    ? `${month(weekStart)} ${day(weekStart)}–${day(end)}`
    : `${month(weekStart)} ${day(weekStart)} – ${month(end)} ${day(end)}`;
}
