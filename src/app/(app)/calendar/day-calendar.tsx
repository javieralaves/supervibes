"use client";

import { useEffect, useRef, useSyncExternalStore } from "react";

import { goalColorStyle } from "@/lib/goal-colors";
import { clockLabel, DAY_MINUTES, planDay } from "@/lib/plan-day";

export type CalendarGoal = { id: string; title: string; icon: string; color: string };
export type CalendarGroup = {
  goal: CalendarGoal;
  suggestions: { title: string; why: string; minutes: number }[];
};

type Item = { key: string; title: string; minutes: number; goal: CalendarGoal };

/** Height of one hour on the timeline, in px. */
const HOUR = 64;
/** Room above midnight and below the last hour so their labels aren't clipped. */
const PAD = 12;
/** Width of the hour-label column. */
const GUTTER = "3.5rem";

const y = (minutes: number) => PAD + (minutes / 60) * HOUR;

/* The clock ticks per minute in the browser only; the server has no idea of the viewer's time. */
function subscribe(onChange: () => void) {
  const id = setInterval(onChange, 15_000);
  return () => clearInterval(id);
}
const minuteNow = () => Math.floor(Date.now() / 60_000);
const noClock = () => null;

/** Today, hour by hour, with every goal's open suggestions placed in the time that's left. */
export function DayCalendar({ groups }: { groups: CalendarGroup[] }) {
  const stamp = useSyncExternalStore(subscribe, minuteNow, noClock);
  const date = stamp === null ? null : new Date(stamp * 60_000);
  const now = date ? date.getHours() * 60 + date.getMinutes() : null;

  const { placed } =
    now === null
      ? { placed: [] }
      : planDay(
          groups.map((g) =>
            g.suggestions.map((s): Item => ({ key: `${g.goal.id}:${s.title}`, title: s.title, minutes: s.minutes, goal: g.goal })),
          ),
          now,
        );
  const count = groups.reduce((n, g) => n + g.suggestions.length, 0);

  // Open on the current time, with about an hour of the past above it.
  const scroller = useRef<HTMLDivElement>(null);
  const scrolled = useRef(false);
  useEffect(() => {
    if (now === null || scrolled.current || !scroller.current) return;
    scroller.current.scrollTop = Math.max(0, y(now) - HOUR);
    scrolled.current = true;
  }, [now]);

  return (
    <div>
      <p className="mb-3 flex flex-wrap items-baseline gap-x-2 text-sm text-muted" suppressHydrationWarning>
        <span className="font-semibold text-foreground">
          {date ? date.toLocaleDateString(undefined, { weekday: "long", month: "long", day: "numeric" }) : "Today"}
        </span>
      </p>

      {count === 0 && (
        <p className="mb-3 rounded-2xl border border-dashed border-foreground/15 p-4 text-sm text-muted">
          No suggestions yet. Each goal&apos;s status update brings two or three, and they show up here.
        </p>
      )}

      <div className="overflow-hidden rounded-2xl border border-card-border bg-card">
        <div ref={scroller} className="h-[calc(100dvh-12rem)] min-h-[420px] overflow-y-auto overscroll-contain">
          <div className="relative" style={{ height: y(DAY_MINUTES) + PAD }}>
            {/* Hour lines and labels */}
            {Array.from({ length: 25 }, (_, h) => {
              const nearNow = now !== null && Math.abs(h * 60 - now) < 14;
              return (
                <div key={h} className="absolute inset-x-0" style={{ top: y(h * 60) }}>
                  <span
                    className={`absolute -translate-y-1/2 pr-2 text-right text-[11px] tabular-nums text-muted transition-opacity ${
                      nearNow ? "opacity-0" : ""
                    }`}
                    style={{ width: GUTTER }}
                  >
                    {h < 24 ? clockLabel(h * 60) : ""}
                  </span>
                  <div className="absolute right-0 border-t border-card-border" style={{ left: GUTTER }} />
                </div>
              );
            })}

            {/* What's already gone today */}
            {now !== null && (
              <div
                aria-hidden="true"
                className="absolute right-0 bg-foreground/[.03]"
                style={{ left: GUTTER, top: PAD, height: y(now) - PAD }}
              />
            )}

            {/* Suggestions */}
            <ol aria-label="Suggestions placed today">
              {placed.map(({ item, start, end }) => (
                <Block key={item.key} item={item} start={start} end={end} />
              ))}
            </ol>

            {/* Now */}
            {now !== null && (
              <div className="pointer-events-none absolute inset-x-0 z-10" style={{ top: y(now) }}>
                <span
                  className="absolute -translate-y-1/2 pr-2 text-right text-[11px] font-semibold tabular-nums text-red-500"
                  style={{ width: GUTTER }}
                >
                  {clockLabel(now)}
                </span>
                <div className="absolute right-0 border-t-2 border-red-500" style={{ left: GUTTER }}>
                  <span className="absolute -left-[5px] -top-[6px] h-2.5 w-2.5 rounded-full bg-red-500" />
                </div>
              </div>
            )}
          </div>
        </div>
      </div>
    </div>
  );
}

function Block({ item, start, end }: { item: Item; start: number; end: number }) {
  const short = item.minutes < 60;
  const time = `${clockLabel(start)}–${clockLabel(end)}`;

  return (
    <li
      style={{ ...goalColorStyle(item.goal.color), top: y(start) + 1, height: y(end) - y(start) - 2, left: `calc(${GUTTER} + 4px)` }}
      className="goal-tint goal-tint-opaque absolute right-2 overflow-hidden rounded-lg"
      title={`${item.title}\n${item.goal.title} · ${time}`}
    >
      <span aria-hidden="true" className="goal-solid absolute inset-y-0 left-0 w-[3px]" />
      {short ? (
        <div className="flex h-full items-center gap-2 pl-3 pr-2.5">
          <p className="min-w-0 flex-1 truncate text-[13px] font-medium text-foreground">{item.title}</p>
          <span className="shrink-0 text-[11px] tabular-nums text-muted">{time}</span>
        </div>
      ) : (
        <div className="flex h-full flex-col gap-1 py-2 pl-3 pr-2.5">
          <p className="line-clamp-2 text-sm font-medium leading-snug text-foreground">
            {item.title}
          </p>
          <p className="text-xs tabular-nums text-muted">{time}</p>
        </div>
      )}
    </li>
  );
}
