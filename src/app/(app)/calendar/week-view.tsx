"use client";

import { Add01Icon, Calendar03Icon, Flag02Icon, Target02Icon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import * as DropdownMenu from "@radix-ui/react-dropdown-menu";
import { useEffect, useRef, useState, useTransition } from "react";

import { GoalBadge } from "@/components/goal-badge";
import { BLOCK_STEP, type BlockDetails, type BlockView } from "@/lib/block-schema";
import { formatHour, formatRange } from "@/lib/clock";
import { DAY_MINUTES, sleepSpans, type DaySegment } from "@/lib/day";
import { goalColorStyle } from "@/lib/goal-colors";
import type { Clock, Settings } from "@/lib/settings-schema";
import { formatWeek } from "@/lib/target-date";
import { MAX_WEEK_OBJECTIVE } from "@/lib/week-objective-schema";

import { setWeekObjectiveAction } from "../goals/[id]/actions";
import { BlockPopover } from "./block-popover";
import type { CalendarGoal } from "./calendar-items";
import type { StripItem } from "./day-strip";
import { GoalSplitBar, PanelFigure, PanelHeader } from "./panel-header";

/*
 * The week at a glance, Monday to Sunday: seven days side by side with what's
 * planned for each day without a time, and the blocks, filled in where time has
 * passed. Drag on a day's empty time (or click it) to protect time for a goal,
 * and drag a block to move it to another time or day, or its top or bottom edge
 * to change its length, as in the day view; click a block to open it, or a day
 * to step into it. Beside it, an
 * overview panel: each goal's objective for the week, and its time planned and done.
 */

/** Height of one hour, in px: close to the day view's (176), so blocks stay readable; the grid scrolls. */
const WEEK_HOUR = 150;
const PAD = 8;
const GUTTER = "3.25rem";
const wy = (minutes: number) => PAD + (minutes / 60) * WEEK_HOUR;
const GRID_HEIGHT = wy(DAY_MINUTES) + PAD;
/** Planned-for-the-day tasks shown per day before "+N". */
const MAX_ANYTIME = 3;
/** Minutes after midnight at a y offset on the week's timeline, unrounded. */
const minutesAtY = (px: number) => ((px - PAD) / WEEK_HOUR) * 60;
const snapDown = (m: number) => Math.floor(m / BLOCK_STEP) * BLOCK_STEP;
const snapUp = (m: number) => Math.ceil(m / BLOCK_STEP) * BLOCK_STEP;
const clampDay = (m: number) => Math.min(DAY_MINUTES, Math.max(0, m));
/** How wide the popover is beside a day, in px. */
const POPOVER_WIDTH = 300;

/** Protected time being drawn on one day: where the press started, and where the pointer is. */
type Drawing = { day: number; from: number; to: number; moved: boolean; originY: number };

/** The span a drawing covers, snapped: a click makes an hour; a drag covers what it passed, at least a step. */
function drawnSpan(d: Drawing) {
  if (!d.moved) {
    let start = snapDown(d.from);
    const end = Math.min(DAY_MINUTES, start + 60);
    if (end - start < BLOCK_STEP) start = end - BLOCK_STEP;
    return { start, end };
  }
  const start = snapDown(Math.min(d.from, d.to));
  return { start, end: Math.max(start + BLOCK_STEP, snapUp(Math.max(d.from, d.to))) };
}

/** Where the popover sits beside day `index` (0 is Monday) of the week's columns. */
function popoverPlace(index: number) {
  const column = `((100% - ${GUTTER}) / 7)`;
  const left =
    index < 5
      ? `calc(${GUTTER} + ${column} * ${index + 1} + 6px)`
      : `calc(${GUTTER} + ${column} * ${index} - ${POPOVER_WIDTH}px - 6px)`;
  return { left, width: `${POPOVER_WIDTH}px` };
}

/**
 * A block being dragged: the whole of it ("move"), or its top or bottom edge. How far
 * it's gone, in minutes and (when moving) days, and whether it's past a click yet.
 */
type BlockDrag = {
  blockId: string;
  day: number;
  mode: "move" | "start" | "end";
  delta: number;
  dayDelta: number;
  moved: boolean;
};

/** Where a block's part on a day sits, shifted by a drag if it's this one. */
function dragged(s: DaySegment, d: BlockDrag | null): DaySegment {
  if (!d || d.blockId !== s.id || d.day !== s.day) return s;
  if (d.mode === "start") return { ...s, start: s.start + d.delta };
  if (d.mode === "end") return { ...s, end: s.end + d.delta };
  return { ...s, day: s.day + d.dayDelta, start: s.start + d.delta, end: s.end + d.delta };
}

/** Protected time drawn on the week and waiting to be named, as the calendar holds it. */
export type WeekCreating = { day: number; start: number; end: number; initial: BlockDetails };

/** "45m", "2h", "2h 30m". */
function duration(minutes: number) {
  const h = Math.floor(minutes / 60);
  const m = Math.round(minutes % 60);
  return h === 0 ? `${m}m` : m === 0 ? `${h}h` : `${h}h ${m}m`;
}

export function WeekView({
  base,
  monday,
  now,
  segments,
  blocks,
  goalById,
  stripFor,
  settings,
  clock,
  selectedId,
  onOpenBlock,
  onOpenDay,
  goals,
  creating,
  onCreate,
  onSaveCreate,
  onCancelCreate,
  onResize,
}: {
  /** Local midnight today. */
  base: Date;
  /** The week's Monday, in days from today. */
  monday: number;
  now: Date;
  /** Every block's parts, by day; the week's are picked out here. */
  segments: DaySegment[];
  blocks: Map<string, BlockView>;
  goalById: Map<string, CalendarGoal>;
  /** A day's tasks planned without a time, and due then. */
  stripFor: (day: number) => StripItem[];
  settings: Settings;
  clock: Clock;
  selectedId: string | null;
  onOpenBlock: (blockId: string) => void;
  onOpenDay: (day: number) => void;
  /** Goals to protect time for, for the popover's goal list. */
  goals: CalendarGoal[];
  /** Time drawn and waiting to be named, if any. */
  creating: WeekCreating | null;
  /** Time drawn on a day: open the popover to name it and pick its goal. */
  onCreate: (day: number, start: number, end: number) => void;
  onSaveCreate: (details: BlockDetails) => void;
  onCancelCreate: () => void;
  /** A block's new times after it, or one of its edges, was dragged. */
  onResize: (block: BlockView, times: { startsAt: string; endsAt: string }) => void;
}) {
  const [blockDrag, setBlockDrag] = useState<BlockDrag | null>(null);
  // A drag that ends over the block would also click it; that click shouldn't open the panel.
  const justDragged = useRef(false);
  // The drag's cursor everywhere while it lasts, even off the block.
  const dragCursor = !blockDrag ? null : blockDrag.mode === "move" ? (blockDrag.moved ? "grabbing" : null) : "ns-resize";
  useEffect(() => {
    if (!dragCursor) return;
    const cursor = document.body.style.cursor;
    document.body.style.cursor = dragCursor;
    return () => {
      document.body.style.cursor = cursor;
    };
  }, [dragCursor]);

  /**
   * Drag a block, as in the day view: the whole of it to another time or day of the
   * week, or its top or bottom edge to change its length. Snapped to steps and kept
   * within its day (and at least a step long). A press that doesn't move is a click.
   */
  function startDrag(e: React.PointerEvent<HTMLElement>, block: BlockView, s: DaySegment, mode: BlockDrag["mode"]) {
    if (e.button !== 0 || block.id.startsWith("pending-")) return;
    if ((e.target as HTMLElement).closest("[data-edge]") && mode === "move") return;
    e.preventDefault();
    e.stopPropagation();
    const originX = e.clientX;
    const originY = e.clientY;
    // One day's column, for how many days a sideways drag has crossed.
    const columnWidth = (timeline.current?.querySelector(".grid-cols-7")?.getBoundingClientRect().width ?? 700) / 7;
    const [min, max] =
      mode === "start"
        ? [-s.start, s.end - BLOCK_STEP - s.start]
        : mode === "end"
          ? [s.start + BLOCK_STEP - s.end, DAY_MINUTES - s.end]
          : [-s.start, DAY_MINUTES - s.end];
    let state: BlockDrag = { blockId: block.id, day: s.day, mode, delta: 0, dayDelta: 0, moved: mode !== "move" };
    setBlockDrag(state);

    function onMove(ev: PointerEvent) {
      const moved = state.moved || Math.hypot(ev.clientX - originX, ev.clientY - originY) > 4;
      const raw = Math.round(((ev.clientY - originY) / WEEK_HOUR) * 60 / BLOCK_STEP) * BLOCK_STEP;
      const delta = Math.max(min, Math.min(max, raw));
      const dayDelta =
        mode === "move"
          ? Math.max(monday - s.day, Math.min(monday + 6 - s.day, Math.round((ev.clientX - originX) / columnWidth)))
          : 0;
      if (moved === state.moved && delta === state.delta && dayDelta === state.dayDelta) return;
      state = { ...state, moved, delta, dayDelta };
      setBlockDrag(state);
    }
    function finish(save: boolean) {
      window.removeEventListener("pointermove", onMove);
      window.removeEventListener("pointerup", onUp);
      window.removeEventListener("pointercancel", onCancel);
      window.removeEventListener("keydown", onKey);
      setBlockDrag(null);
      // Pressed and let go without moving: a click, which opens the block.
      if (!state.moved) return;
      justDragged.current = true;
      setTimeout(() => (justDragged.current = false), 0);
      if (!save || (state.delta === 0 && state.dayDelta === 0)) return;
      const { delta, dayDelta } = state;
      // Days by the calendar (so a daylight-saving change keeps the clock time), then minutes.
      const shifted = (iso: string, shift: boolean) => {
        if (!shift) return iso;
        const d = new Date(iso);
        d.setDate(d.getDate() + dayDelta);
        return new Date(d.getTime() + delta * 60_000).toISOString();
      };
      onResize(block, {
        startsAt: shifted(block.startsAt, mode !== "end"),
        endsAt: shifted(block.endsAt, mode !== "start"),
      });
    }
    const onUp = () => finish(true);
    const onCancel = () => finish(false);
    const onKey = (ev: KeyboardEvent) => {
      if (ev.key === "Escape") finish(false);
    };
    window.addEventListener("pointermove", onMove);
    window.addEventListener("pointerup", onUp);
    window.addEventListener("pointercancel", onCancel);
    window.addEventListener("keydown", onKey);
  }

  const [drawing, setDrawingState] = useState<Drawing | null>(null);
  // Also kept in a ref, so a quick tap's release sees the press before React re-renders.
  const drawingRef = useRef<Drawing | null>(null);
  const setDrawing = (d: Drawing | null) => {
    drawingRef.current = d;
    setDrawingState(d);
  };
  const timeline = useRef<HTMLDivElement>(null);
  const minuteAt = (clientY: number) => clampDay(minutesAtY(clientY - timeline.current!.getBoundingClientRect().top));

  function onColumnDown(e: React.PointerEvent<HTMLDivElement>, day: number) {
    // Empty time only: blocks open on click, and the overlays let presses through.
    if (e.button !== 0 || e.target !== e.currentTarget || !timeline.current) return;
    // Keep getting moves while the pointer leaves the column; not every pointer can be captured.
    try {
      e.currentTarget.setPointerCapture(e.pointerId);
    } catch {}
    const m = minuteAt(e.clientY);
    setDrawing({ day, from: m, to: m, moved: false, originY: e.clientY });
  }
  function onColumnMove(e: React.PointerEvent<HTMLDivElement>) {
    const d = drawingRef.current;
    if (!d) return;
    setDrawing({ ...d, to: minuteAt(e.clientY), moved: d.moved || Math.abs(e.clientY - d.originY) > 4 });
  }
  function onColumnUp() {
    const d = drawingRef.current;
    if (!d) return;
    const { start, end } = drawnSpan(d);
    setDrawing(null);
    onCreate(d.day, start, end);
  }

  // The dashed outline of time being drawn, or drawn and waiting to be named.
  const draft = drawing?.moved ? { day: drawing.day, ...drawnSpan(drawing) } : creating;
  const days = Array.from({ length: 7 }, (_, i) => monday + i);
  const inWeek = segments.filter((s) => s.day >= monday && s.day <= monday + 6);
  /** A local time, `minutes` after midnight `day` days from today, in ms. */
  const at = (day: number, minutes: number) =>
    new Date(base.getFullYear(), base.getMonth(), base.getDate() + day, 0, minutes).getTime();
  const nowMin = now.getHours() * 60 + now.getMinutes();
  const elapsedOf = (s: DaySegment) => elapsed(s, base, now);

  const anytime = days.map((d) => stripFor(d));
  const hasAnytime = anytime.some((items) => items.length > 0);

  // Open on the current time (or waking up, on other weeks), with about an hour above it.
  const scroller = useRef<HTMLDivElement>(null);
  const thisWeek = monday <= 0 && monday + 6 >= 0;
  useEffect(() => {
    if (!scroller.current) return;
    const focus = thisWeek ? new Date().getHours() * 60 + new Date().getMinutes() : settings.wakeTime;
    scroller.current.scrollTop = Math.max(0, wy(focus) - WEEK_HOUR);
  }, [monday, thisWeek, settings.wakeTime]);

  const sleep = sleepSpans(settings);

  return (
    <div className="flex min-h-0 min-w-0 flex-1 flex-col overflow-hidden rounded-2xl border border-card-border bg-card">
        {/* Day names, then each day's tasks planned without a time. */}
        <div className="shrink-0 border-b border-card-border">
          <div className="grid" style={{ gridTemplateColumns: `${GUTTER} repeat(7, minmax(0, 1fr))` }}>
            <span />
            {days.map((d) => {
              const date = new Date(base.getFullYear(), base.getMonth(), base.getDate() + d);
              const isToday = d === 0;
              return (
                <button
                  key={d}
                  type="button"
                  onClick={() => onOpenDay(d)}
                  title="Open this day"
                  className="flex items-baseline justify-center gap-1.5 border-l border-card-border py-2 text-sm transition-colors hover:bg-wash"
                >
                  <span className={isToday ? "font-semibold text-foreground" : "text-muted"}>
                    {date.toLocaleDateString(undefined, { weekday: "short" })}
                  </span>
                  <span
                    className={`tabular-nums ${
                      isToday
                        ? "flex h-6 min-w-6 items-center justify-center rounded-full bg-foreground px-1 text-xs font-semibold text-background"
                        : "text-foreground"
                    }`}
                  >
                    {date.getDate()}
                  </span>
                </button>
              );
            })}
          </div>
          {hasAnytime && (
            <div className="grid" style={{ gridTemplateColumns: `${GUTTER} repeat(7, minmax(0, 1fr))` }}>
              <span className="pr-2 pt-1.5 text-right text-[10px] font-medium text-muted">Anytime</span>
              {days.map((d, i) => (
                <AnytimeDay
                  key={d}
                  items={anytime[i]}
                  goalById={goalById}
                  onOpen={() => onOpenDay(d)}
                />
              ))}
            </div>
          )}
        </div>

        <div
          ref={scroller}
          aria-label="Week timeline"
          className="min-h-0 flex-1 overflow-y-auto overscroll-contain"
        >
          <div ref={timeline} className="relative" style={{ height: GRID_HEIGHT }}>
            {/* Hour lines and labels */}
            {Array.from({ length: 25 }, (_, h) => (
              <div key={h} aria-hidden="true" className="absolute inset-x-0" style={{ top: wy(h * 60) }}>
                <div className="absolute right-0 border-t border-card-border" style={{ left: GUTTER }} />
                {h > 0 && h < 24 && (
                  <span
                    className="absolute -translate-y-1/2 pr-2 text-right text-[10px] tabular-nums text-muted"
                    style={{ width: GUTTER }}
                  >
                    {formatHour(h, clock)}
                  </span>
                )}
              </div>
            ))}

            <div className="absolute inset-y-0 right-0 grid grid-cols-7" style={{ left: GUTTER }}>
              {days.map((d) => {
                // Whole days behind you, and today up to now, are washed slightly: time that's gone.
                const pastUntil = d < 0 ? DAY_MINUTES : d === 0 ? nowMin : null;
                return (
                  <div
                    key={d}
                    onPointerDown={(e) => onColumnDown(e, d)}
                    onPointerMove={onColumnMove}
                    onPointerUp={onColumnUp}
                    onPointerCancel={() => setDrawing(null)}
                    className={`relative touch-none select-none border-l border-card-border ${
                      drawing?.day === d && drawing.moved ? "cursor-ns-resize" : ""
                    }`}
                  >
                    {sleep.map((span) => (
                      <div
                        key={span.start}
                        aria-hidden="true"
                        className="pointer-events-none absolute inset-x-0 bg-[repeating-linear-gradient(135deg,color-mix(in_oklab,var(--foreground)_6%,transparent)_0_1px,transparent_1px_7px)]"
                        style={{ top: wy(span.start), height: wy(span.end) - wy(span.start) }}
                      />
                    ))}
                    {pastUntil !== null && (
                      <div
                        aria-hidden="true"
                        className="pointer-events-none absolute inset-x-0 bg-foreground/[.03]"
                        style={{ top: PAD, height: wy(pastUntil) - PAD }}
                      />
                    )}
                    {inWeek
                      .map((s) => ({ s, shown: dragged(s, blockDrag) }))
                      .filter(({ shown }) => shown.day === d)
                      .map(({ s, shown }) => {
                        const block = blocks.get(s.id);
                        if (!block) return null;
                        // Only the day a block starts on has its top edge, and the day it ends on its bottom;
                        // only a block within one day moves as a whole.
                        const startsHere = at(s.day, s.start) === Date.parse(block.startsAt);
                        const endsHere = at(s.day, s.end) === Date.parse(block.endsAt);
                        return (
                          <WeekBlock
                            key={`${s.id}:${s.day}`}
                            block={block}
                            goal={goalById.get(block.goalId)}
                            start={shown.start}
                            end={shown.end}
                            elapsed={elapsedOf(shown)}
                            clock={clock}
                            selected={block.id === selectedId}
                            dragging={blockDrag?.blockId === s.id && blockDrag.moved}
                            onBodyDown={startsHere && endsHere ? (e) => startDrag(e, block, s, "move") : undefined}
                            onStartEdge={startsHere ? (e) => startDrag(e, block, s, "start") : undefined}
                            onEndEdge={endsHere ? (e) => startDrag(e, block, s, "end") : undefined}
                            onOpen={() => {
                              if (!justDragged.current) onOpenBlock(block.id);
                            }}
                          />
                        );
                      })}
                    {draft && draft.day === d && (
                      <div
                        aria-hidden="true"
                        className="pointer-events-none absolute inset-x-0.5 z-30 rounded-md border-2 border-dashed border-foreground/40 bg-foreground/[.04]"
                        style={{ top: wy(draft.start) + 1, height: wy(draft.end) - wy(draft.start) - 2 }}
                      >
                        <span className="absolute left-2 top-1 text-[11px] font-medium tabular-nums text-muted">
                          {formatRange(draft.start, draft.end, clock)}
                        </span>
                      </div>
                    )}
                    {d === 0 && (
                      <div
                        aria-hidden="true"
                        className="pointer-events-none absolute inset-x-0 z-20 border-t-2 border-red-500"
                        style={{ top: wy(nowMin) - 1 }}
                      >
                        <span className="absolute -left-1 -top-[5px] h-2 w-2 rounded-full bg-red-500" />
                      </div>
                    )}
                  </div>
                );
              })}
            </div>

            {/* Naming time just drawn: beside its day, to the right, or to the left on the weekend so it stays in view. */}
            {creating && creating.day >= monday && creating.day <= monday + 6 && (
              <BlockPopover
                key={`new-${creating.day}-${creating.start}`}
                // Aligned with the drawn time's top edge (or its bottom, near the end of the day) rather than under it.
                anchorTop={wy(creating.end) + 8}
                anchorBottom={wy(creating.start) - 8}
                timelineHeight={GRID_HEIGHT}
                goals={goals}
                initial={creating.initial}
                intention={false}
                timeLabel={`${new Date(base.getFullYear(), base.getMonth(), base.getDate() + creating.day).toLocaleDateString(undefined, { weekday: "long" })} · ${formatRange(creating.start, creating.end, clock)}`}
                place={popoverPlace(creating.day - monday)}
                onSave={onSaveCreate}
                onCancel={onCancelCreate}
              />
            )}
          </div>
        </div>
    </div>
  );
}

/** How much of a block's part on a day has happened, 0 to 1. */
function elapsed(s: DaySegment, base: Date, now: Date) {
  const at = (minutes: number) =>
    new Date(base.getFullYear(), base.getMonth(), base.getDate() + s.day, 0, minutes).getTime();
  const from = at(s.start);
  const to = at(s.end);
  return to > from ? Math.min(1, Math.max(0, (now.getTime() - from) / (to - from))) : 0;
}

export type WeekTotals = Map<string, { planned: number; done: number }>;

/** Each goal's time in the week starting `monday` days from today: all of it, and how much has happened, in minutes. */
export function weekTotals(segments: DaySegment[], monday: number, base: Date, now: Date): WeekTotals {
  const totals: WeekTotals = new Map();
  for (const s of segments) {
    if (s.day < monday || s.day > monday + 6) continue;
    const t = totals.get(s.goalId) ?? { planned: 0, done: 0 };
    t.planned += s.end - s.start;
    t.done += (s.end - s.start) * elapsed(s, base, now);
    totals.set(s.goalId, t);
  }
  return totals;
}

/**
 * The week's overview, beside the calendar. First each goal's time as a bar: bars
 * share one scale, the goal with the most time filling the width, so they compare
 * at a glance (light: planned, solid: happened). Then the week's objectives, each
 * editable in place, and "Add weekly objective" for goals that don't have one yet.
 */
export function WeekOverview({
  goals,
  totals,
  objectives,
  weekStart,
}: {
  goals: CalendarGoal[];
  totals: WeekTotals;
  /** This week's objective for each goal that has one. */
  objectives: Map<string, string>;
  /** The Monday this week starts on, "YYYY-MM-DD". */
  weekStart: string;
}) {
  // Goals picked from "Add weekly objective" that aren't saved yet, for this week.
  const [adding, setAdding] = useState<{ weekStart: string; ids: string[] }>({ weekStart, ids: [] });
  const added = adding.weekStart === weekStart ? adding.ids : [];
  const addGoal = (id: string) => setAdding({ weekStart, ids: [...added, id] });
  const dropGoal = (id: string) => setAdding({ weekStart, ids: added.filter((g) => g !== id) });

  // Goals with time this week first, most time first; then the rest, in their order.
  const byTime = goals.toSorted((a, b) => (totals.get(b.id)?.planned ?? 0) - (totals.get(a.id)?.planned ?? 0));
  const most = Math.max(0, ...[...totals.values()].map((t) => t.planned));
  const withObjective = goals.filter((g) => objectives.has(g.id) || added.includes(g.id));
  const without = goals.filter((g) => !objectives.has(g.id) && !added.includes(g.id));
  const planned = [...totals.values()].reduce((n, t) => n + t.planned, 0);
  const done = [...totals.values()].reduce((n, t) => n + t.done, 0);

  return (
    <aside
      aria-label="This week"
      className="hidden w-72 shrink-0 flex-col overflow-hidden rounded-2xl border border-card-border bg-card lg:flex"
    >
      <PanelHeader icon={Target02Icon} title="This week" note={formatWeek(weekStart)}>
        <PanelFigure
          value={duration(done)}
          label={planned > 0 ? `done of ${duration(planned)} planned` : "nothing planned yet"}
        />
        <GoalSplitBar
          label={`${duration(done)} done of ${duration(planned)} planned, across goals`}
          parts={byTime.map((goal) => ({
            goalId: goal.id,
            color: goal.color,
            value: totals.get(goal.id)?.planned ?? 0,
            filled: totals.get(goal.id)?.done ?? 0,
          }))}
        />
      </PanelHeader>
      <div className="min-h-0 flex-1 overflow-y-auto overscroll-contain px-4 py-4">
        {goals.length === 0 ? (
          <p className="text-sm text-muted">No goals yet.</p>
        ) : (
          <>
            <section aria-label="Time this week">
              <h3 className="text-[11px] font-medium uppercase tracking-[0.06em] text-muted">By goal</h3>
              <ul className="mt-2 space-y-3">
                {byTime.map((goal) => (
                  <TimeRow key={goal.id} goal={goal} totals={totals.get(goal.id) ?? null} most={most} />
                ))}
              </ul>
            </section>

            <section aria-label="Objectives this week" className="mt-6">
              <h3 className="text-[11px] font-medium uppercase tracking-[0.06em] text-muted">Objectives</h3>
              {withObjective.length > 0 && (
                <ul className="mt-2 space-y-3">
                  {withObjective.map((goal) => (
                    <ObjectiveRow
                      key={`${goal.id}:${weekStart}`}
                      goal={goal}
                      weekStart={weekStart}
                      objective={objectives.get(goal.id) ?? null}
                      // Just picked from the menu: start typing straight away.
                      autoFocus={added.includes(goal.id) && !objectives.has(goal.id)}
                      onSettled={() => dropGoal(goal.id)}
                    />
                  ))}
                </ul>
              )}
              {without.length > 0 && (
                <DropdownMenu.Root>
                  <DropdownMenu.Trigger className="-mx-2 mt-2 flex h-8 items-center gap-1.5 rounded-lg px-2 text-[13px] font-medium text-muted transition-colors hover:bg-wash hover:text-foreground data-[state=open]:bg-wash data-[state=open]:text-foreground">
                    <HugeiconsIcon icon={Add01Icon} size={14} />
                    Add weekly objective
                  </DropdownMenu.Trigger>
                  <DropdownMenu.Portal>
                    <DropdownMenu.Content
                      align="start"
                      sideOffset={6}
                      collisionPadding={12}
                      // Focus goes to the new objective's field, not back to this button.
                      onCloseAutoFocus={(e) => e.preventDefault()}
                      className="z-50 w-64 rounded-xl border border-card-border bg-card p-1 shadow-[0_12px_32px_-12px_rgb(0_0_0/0.25)] outline-none data-[state=open]:animate-[pop-in_120ms_ease-out]"
                    >
                      <DropdownMenu.Label className="px-2.5 pb-1 pt-1.5 text-xs font-medium text-muted">
                        For which goal?
                      </DropdownMenu.Label>
                      {without.map((goal) => (
                        <DropdownMenu.Item
                          key={goal.id}
                          onSelect={() => addGoal(goal.id)}
                          className="flex min-h-8 cursor-default select-none items-center gap-2 rounded-lg px-2.5 py-1.5 text-sm text-foreground outline-none data-[highlighted]:bg-wash"
                        >
                          <GoalBadge icon={goal.icon} color={goal.color} size="xs" />
                          <span className="min-w-0 truncate">{goal.title}</span>
                        </DropdownMenu.Item>
                      ))}
                    </DropdownMenu.Content>
                  </DropdownMenu.Portal>
                </DropdownMenu.Root>
              )}
            </section>
          </>
        )}
      </div>
    </aside>
  );
}

/** A goal's time this week: its title and figures, then a bar on the shared scale. */
function TimeRow({
  goal,
  totals,
  most,
}: {
  goal: CalendarGoal;
  totals: { planned: number; done: number } | null;
  /** The most time any goal has this week, in minutes: the bars' full width. */
  most: number;
}) {
  const planned = totals?.planned ?? 0;
  const done = totals?.done ?? 0;
  const share = (minutes: number) => (most > 0 ? `${(minutes / most) * 100}%` : "0%");
  return (
    <li style={goalColorStyle(goal.color)}>
      <div className="flex items-baseline gap-2">
        <span className="min-w-0 flex-1 truncate text-[13px] text-foreground" title={goal.title}>
          {goal.title}
        </span>
        <span className="shrink-0 text-[11px] tabular-nums text-muted">
          {planned > 0 ? `${duration(done)} / ${duration(planned)}` : "No time"}
        </span>
      </div>
      <div
        role="img"
        aria-label={planned > 0 ? `${duration(done)} done of ${duration(planned)} planned` : "No time this week"}
        className="relative mt-1 h-1"
      >
        {planned > 0 && <span className="goal-track absolute inset-y-0 left-0 rounded-full" style={{ width: share(planned) }} />}
        {done >= 1 && <span className="goal-solid absolute inset-y-0 left-0 rounded-full" style={{ width: share(done) }} />}
      </div>
    </li>
  );
}

/** A block in the week: its goal's colour, filled in as far as its time has passed. Click to open it. */
function WeekBlock({
  block,
  goal,
  start,
  end,
  elapsed,
  clock,
  selected,
  dragging,
  onBodyDown,
  onStartEdge,
  onEndEdge,
  onOpen,
}: {
  block: BlockView;
  goal: CalendarGoal | undefined;
  start: number;
  end: number;
  elapsed: number;
  clock: Clock;
  selected: boolean;
  /** It, or one of its edges, is being dragged. */
  dragging: boolean;
  /** Press on it to drag the whole block; absent for one that crosses midnight. */
  onBodyDown?: (e: React.PointerEvent<HTMLElement>) => void;
  /** Drag its top edge; absent on a day it doesn't start on. */
  onStartEdge?: (e: React.PointerEvent<HTMLElement>) => void;
  /** Drag its bottom edge; absent on a day it doesn't end on. */
  onEndEdge?: (e: React.PointerEvent<HTMLElement>) => void;
  onOpen: () => void;
}) {
  const intention = Boolean(block.fromSuggestion || block.taskId);
  const title = block.title ?? goal?.title ?? "Protected time";
  const time = formatRange(start, end, clock);
  const height = Math.max(wy(end) - wy(start) - 2, 6);
  const pending = block.id.startsWith("pending-");
  return (
    <button
      type="button"
      onClick={pending ? undefined : onOpen}
      onPointerDown={pending ? undefined : onBodyDown}
      aria-label={`${intention ? (block.taskDone ? "Done" : "Intention") : "Protected time"}: ${title}, ${time}`}
      title={`${title}\n${time}`}
      style={{
        ...goalColorStyle(goal?.color ?? "slate"),
        top: wy(start) + 1,
        height,
        ["--elapsed" as string]: `${Math.round(elapsed * 1000) / 10}%`,
      }}
      // A flex column so the title sits at the top: a button centres its content otherwise.
      className={`goal-tint ${intention ? "goal-tint-opaque" : "goal-hatch"} block-time group absolute inset-x-0.5 flex flex-col justify-start overflow-hidden rounded-md text-left ${
        dragging ? "z-30 shadow-[0_8px_20px_-8px_rgb(15_17_20/0.35)]" : "z-10"
      } ${selected ? "ring-2 ring-[var(--goal)]/60" : ""} ${pending ? "opacity-60" : dragging ? "cursor-grabbing" : "cursor-pointer"}`}
    >
      <span aria-hidden="true" className="block-bar absolute inset-y-0 left-0 w-[3px]" />
      {/* Drag the top or bottom edge to change the length, as in the day view. */}
      {!pending && onStartEdge && (
        <span
          aria-hidden="true"
          data-edge="start"
          onPointerDown={onStartEdge}
          className="absolute inset-x-0 top-0 z-10 h-1.5 cursor-ns-resize"
        />
      )}
      {!pending && onEndEdge && (
        <span
          aria-hidden="true"
          data-edge="end"
          onPointerDown={onEndEdge}
          className="absolute inset-x-0 bottom-0 z-10 flex h-2 cursor-ns-resize justify-center"
        >
          <span
            className={`mt-0.5 h-1 w-6 rounded-full bg-foreground/20 transition-opacity group-hover:opacity-100 ${
              dragging ? "opacity-100" : "opacity-0"
            }`}
          />
        </span>
      )}
      {height >= 18 && (
        <span className={`block px-2 ${height >= 44 ? "pt-1.5" : "pt-0.5"}`}>
          <span
            className={`block text-[12.5px] font-medium leading-snug ${
              block.taskDone ? "text-muted line-through decoration-foreground/25" : "text-foreground"
            } ${height >= 110 ? "line-clamp-3" : height >= 60 ? "line-clamp-2" : "truncate"}`}
          >
            {title}
          </span>
          {height >= 60 && <span className="mt-0.5 block truncate text-[11px] tabular-nums text-muted">{time}</span>}
        </span>
      )}
    </button>
  );
}

/** A day's tasks planned without a time, and due then, under its name. Click to step into the day. */
function AnytimeDay({
  items,
  goalById,
  onOpen,
}: {
  items: StripItem[];
  goalById: Map<string, CalendarGoal>;
  onOpen: () => void;
}) {
  const shown = items.slice(0, MAX_ANYTIME);
  const more = items.length - shown.length;
  return (
    <div className="flex min-w-0 flex-col gap-0.5 border-l border-card-border px-1 pb-1.5 pt-1">
      {shown.map(({ task, due }) => (
        <button
          key={task.id}
          type="button"
          onClick={onOpen}
          title={task.title}
          style={goalColorStyle(goalById.get(task.goalId)?.color ?? "slate")}
          className="goal-tint flex min-w-0 items-center gap-1 rounded px-1.5 py-0.5 text-left transition-[filter] hover:brightness-95 dark:hover:brightness-125"
        >
          <HugeiconsIcon
            icon={due ? Flag02Icon : Calendar03Icon}
            size={10}
            className={`shrink-0 ${due === "overdue" ? "text-red-600 dark:text-red-400" : ""}`}
          />
          <span className="truncate text-[11px] font-medium text-foreground">{task.title}</span>
        </button>
      ))}
      {more > 0 && (
        <button type="button" onClick={onOpen} className="px-1.5 text-left text-[11px] text-muted hover:text-foreground">
          +{more} more
        </button>
      )}
    </div>
  );
}

/**
 * One goal's objective for the week, editable in place: saved when the field loses
 * focus, cleared by emptying it. A row just added from the menu goes again if left empty.
 */
function ObjectiveRow({
  goal,
  weekStart,
  objective,
  autoFocus,
  onSettled,
}: {
  goal: CalendarGoal;
  weekStart: string;
  objective: string | null;
  autoFocus: boolean;
  /** Once a new row is saved or abandoned, it's no longer "being added". */
  onSettled: () => void;
}) {
  const [draft, setDraft] = useState(objective ?? "");
  const [error, setError] = useState<string | null>(null);
  const [, startSaving] = useTransition();
  const field = useRef<HTMLTextAreaElement>(null);

  // A row just picked from the menu: focus it once the menu has closed.
  useEffect(() => {
    if (!autoFocus) return;
    const frame = requestAnimationFrame(() => field.current?.focus());
    return () => cancelAnimationFrame(frame);
  }, [autoFocus]);

  function save() {
    const value = draft.trim();
    if (value === (objective ?? "")) {
      if (!value) onSettled();
      return;
    }
    setError(null);
    startSaving(async () => {
      const result = await setWeekObjectiveAction(goal.id, weekStart, value);
      if (result.ok) onSettled();
      else setError(result.error);
    });
  }

  return (
    <li style={goalColorStyle(goal.color)}>
      <p className="flex min-w-0 items-center gap-1.5 text-[11px] font-medium text-muted">
        <span aria-hidden="true" className="goal-solid h-1.5 w-1.5 shrink-0 rounded-full" />
        <span className="truncate" title={goal.title}>
          {goal.title}
        </span>
      </p>
      <textarea
        ref={field}
        aria-label={`What this week should move for ${goal.title}`}
        value={draft}
        maxLength={MAX_WEEK_OBJECTIVE}
        rows={1}
        onChange={(e) => setDraft(e.target.value)}
        onBlur={save}
        onKeyDown={(e) => {
          if (e.key === "Enter" && !e.shiftKey) {
            e.preventDefault();
            e.currentTarget.blur();
          }
          if (e.key === "Escape") {
            setDraft(objective ?? "");
            requestAnimationFrame(() => (e.target as HTMLTextAreaElement).blur());
          }
        }}
        placeholder="What should this week move?"
        className="-mx-1.5 mt-0.5 block w-[calc(100%+0.75rem)] resize-none rounded-md bg-transparent px-1.5 py-1 text-[13px] leading-snug text-foreground outline-none transition-colors [field-sizing:content] placeholder:text-muted/70 hover:bg-wash/60 focus:bg-wash/60"
      />
      {error && (
        <p role="alert" className="mt-1 text-xs text-red-600 dark:text-red-400">
          {error}
        </p>
      )}
    </li>
  );
}
