"use client";

import { ArrowLeft01Icon, ArrowRight01Icon, Moon02Icon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon, type IconSvgElement } from "@hugeicons/react";
import { useEffect, useRef, useState, useSyncExternalStore } from "react";

import { formatHour, formatRange, formatTime, useClock } from "@/lib/clock";
import { goalColorStyle } from "@/lib/goal-colors";
import { DAY_MINUTES, planDays, sleepSpans } from "@/lib/plan-day";
import type { Clock, Settings } from "@/lib/settings-schema";

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
const GUTTER = "4rem";

const y = (minutes: number) => PAD + (minutes / 60) * HOUR;

/* The clock ticks per minute in the browser only; the server has no idea of the viewer's time. */
function subscribe(onChange: () => void) {
  const id = setInterval(onChange, 15_000);
  return () => clearInterval(id);
}
const minuteNow = () => Math.floor(Date.now() / 60_000);
const noClock = () => null;

const DAY_MS = 24 * 60 * 60 * 1000;

function dayLabel(offset: number) {
  return offset === 0 ? "Today" : offset === 1 ? "Tomorrow" : offset === -1 ? "Yesterday" : null;
}

/**
 * One day, hour by hour. Every goal's open suggestions are placed in your awake
 * time from now on, spilling into the following days; the chevrons step between days.
 */
export function DayCalendar({ groups, settings }: { groups: CalendarGroup[]; settings: Settings }) {
  const stamp = useSyncExternalStore(subscribe, minuteNow, noClock);
  const clock = useClock(settings.clock);
  const [offset, setOffset] = useState(0);
  const ready = stamp !== null;
  const today = ready ? new Date(stamp * 60_000) : null;
  const now = today ? today.getHours() * 60 + today.getMinutes() : null;
  const isToday = offset === 0;
  // Noon avoids landing on the wrong date across a daylight-saving change.
  const shown = today
    ? new Date(today.getFullYear(), today.getMonth(), today.getDate(), 12).getTime() + offset * DAY_MS
    : null;

  const placed =
    now === null
      ? []
      : planDays(
          groups.map((g) =>
            g.suggestions.map((s): Item => ({ key: `${g.goal.id}:${s.title}`, title: s.title, minutes: s.minutes, goal: g.goal })),
          ),
          now,
          settings,
        ).filter((p) => p.day === offset);
  const count = groups.reduce((n, g) => n + g.suggestions.length, 0);
  // Earlier days are all behind you; later days haven't started.
  const pastUntil = offset < 0 ? DAY_MINUTES : isToday ? now : null;

  // Open on (and come back to) the current time, with about an hour of the past above it.
  const scroller = useRef<HTMLDivElement>(null);
  useEffect(() => {
    if (!ready || offset !== 0 || !scroller.current) return;
    const d = new Date();
    scroller.current.scrollTop = Math.max(0, y(d.getHours() * 60 + d.getMinutes()) - HOUR);
  }, [ready, offset]);

  // ← and → step between days while the pointer is over the calendar or focus is inside it.
  const card = useRef<HTMLDivElement>(null);
  const hovered = useRef(false);
  useEffect(() => {
    if (!ready) return;
    function onKey(e: KeyboardEvent) {
      if (e.key !== "ArrowLeft" && e.key !== "ArrowRight") return;
      if (e.metaKey || e.ctrlKey || e.altKey || e.shiftKey || e.defaultPrevented) return;
      const target = e.target as HTMLElement | null;
      if (target?.closest("input, textarea, select, [contenteditable='true']")) return;
      const focused = card.current?.contains(document.activeElement) ?? false;
      if (!hovered.current && !focused) return;
      e.preventDefault();
      setOffset((o) => o + (e.key === "ArrowLeft" ? -1 : 1));
    }
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [ready]);

  const relative = dayLabel(offset);

  return (
    <div className="flex min-h-0 flex-1 flex-col">
      {count === 0 && (
        <p className="mb-3 shrink-0 rounded-2xl border border-dashed border-foreground/15 p-4 text-sm text-muted">
          No suggestions yet. Each goal&apos;s status update brings two or three, and they show up here.
        </p>
      )}

      <div
        ref={card}
        onPointerEnter={() => (hovered.current = true)}
        onPointerLeave={() => (hovered.current = false)}
        className="flex min-h-0 flex-1 flex-col overflow-hidden rounded-2xl border border-card-border bg-card"
      >
        {/* Day header: step between days on the left, the date beside them. */}
        <div className="flex shrink-0 items-center gap-3 border-b border-card-border px-3 py-3 sm:px-4">
          <div className="flex shrink-0 items-center gap-1">
            <NavButton label="Previous day" icon={ArrowLeft01Icon} disabled={!ready} onClick={() => setOffset((o) => o - 1)} />
            <NavButton label="Next day" icon={ArrowRight01Icon} disabled={!ready} onClick={() => setOffset((o) => o + 1)} />
          </div>
          <h2 aria-live="polite" className="flex min-w-0 items-baseline gap-2" suppressHydrationWarning>
            <span className="truncate text-[15px] font-semibold tracking-[-0.01em] text-foreground">
              {shown === null
                ? "Today"
                : new Date(shown).toLocaleDateString(undefined, { weekday: "long", month: "long", day: "numeric" })}
            </span>
            {shown !== null && relative && <span className="shrink-0 text-sm text-muted">{relative}</span>}
          </h2>
          {!isToday && (
            <button
              type="button"
              onClick={() => setOffset(0)}
              className="ml-auto h-8 shrink-0 rounded-lg border border-card-border bg-card px-3 text-sm font-medium text-foreground shadow-[0_1px_2px_rgb(15_17_20/0.05)] transition-colors hover:border-line-strong"
            >
              Today
            </button>
          )}
        </div>

        <div
          ref={scroller}
          tabIndex={0}
          aria-label="Day timeline. Use the left and right arrow keys to change day."
          className="min-h-0 flex-1 overflow-y-auto overscroll-contain outline-none focus-visible:outline-2 focus-visible:-outline-offset-2 focus-visible:outline-foreground/20"
        >
          <div className="relative" style={{ height: y(DAY_MINUTES) + PAD }}>
            {/* Hour lines and labels */}
            {Array.from({ length: 25 }, (_, h) => {
              const nearNow = isToday && now !== null && Math.abs(h * 60 - now) < 14;
              return (
                <div key={h} className="absolute inset-x-0" style={{ top: y(h * 60) }}>
                  <span
                    className={`absolute -translate-y-1/2 pr-2 text-right text-[11px] tabular-nums text-muted transition-opacity ${
                      nearNow ? "opacity-0" : ""
                    }`}
                    style={{ width: GUTTER }}
                  >
                    {h < 24 ? formatHour(h, clock) : ""}
                  </span>
                  <div className="absolute right-0 border-t border-card-border" style={{ left: GUTTER }} />
                </div>
              );
            })}

            {/* Sleep */}
            {sleepSpans(settings).map((span) => (
              <div
                key={span.start}
                aria-hidden="true"
                className="absolute right-0 bg-[repeating-linear-gradient(135deg,color-mix(in_oklab,var(--foreground)_6%,transparent)_0_1px,transparent_1px_7px)]"
                style={{ left: GUTTER, top: y(span.start), height: y(span.end) - y(span.start) }}
              >
                {span.end - span.start >= 45 && (
                  <span className="absolute left-3 top-2 flex items-center gap-1 text-[11px] font-medium text-muted">
                    <HugeiconsIcon icon={Moon02Icon} size={12} />
                    Sleep
                  </span>
                )}
              </div>
            ))}

            {/* Time that's already gone */}
            {pastUntil !== null && (
              <div
                aria-hidden="true"
                className="absolute right-0 bg-foreground/[.03]"
                style={{ left: GUTTER, top: PAD, height: y(pastUntil) - PAD }}
              />
            )}

            {/* Suggestions */}
            {placed.length > 0 && (
              <ol aria-label="Suggestions on this day">
                {placed.map(({ item, start, end }) => (
                  <Block key={item.key} item={item} start={start} end={end} clock={clock} />
                ))}
              </ol>
            )}

            {/* Now */}
            {isToday && now !== null && (
              <div className="pointer-events-none absolute inset-x-0 z-10" style={{ top: y(now) }}>
                <span
                  className="absolute -translate-y-1/2 pr-2 text-right text-[11px] font-semibold tabular-nums text-red-500"
                  style={{ width: GUTTER }}
                >
                  {formatTime(now, clock)}
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

function NavButton({
  label,
  icon,
  disabled,
  onClick,
}: {
  label: string;
  icon: IconSvgElement;
  disabled: boolean;
  onClick: () => void;
}) {
  return (
    <button
      type="button"
      aria-label={label}
      title={label}
      disabled={disabled}
      onClick={onClick}
      className="flex h-8 w-8 items-center justify-center rounded-lg border border-card-border bg-card text-muted shadow-[0_1px_2px_rgb(15_17_20/0.05)] transition-colors hover:border-line-strong hover:text-foreground disabled:opacity-50"
    >
      <HugeiconsIcon icon={icon} size={16} strokeWidth={2} />
    </button>
  );
}

function Block({ item, start, end, clock }: { item: Item; start: number; end: number; clock: Clock }) {
  const short = item.minutes < 60;
  const time = formatRange(start, end, clock);

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
