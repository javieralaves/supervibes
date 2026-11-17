"use client";

import { ArrowLeft01Icon, ArrowRight01Icon, Moon02Icon, ViewIcon, ViewOffIcon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon, type IconSvgElement } from "@hugeicons/react";
import { startTransition, useCallback, useEffect, useOptimistic, useRef, useState, useSyncExternalStore } from "react";

import type { BlockDetails, BlockView } from "@/lib/block-schema";
import { BLOCK_STEP } from "@/lib/block-schema";
import { formatHour, formatRange, formatTime, useClock } from "@/lib/clock";
import { DAY_MINUTES, planDays, sleepSpans, type PlanBlock, type PlanItem } from "@/lib/plan-day";
import type { Settings } from "@/lib/settings-schema";

import {
  createBlockAction,
  createIntentionAction,
  deleteBlockAction,
  moveBlockAction,
  scheduleTaskAction,
  setBlockTaskDoneAction,
  updateBlockAction,
} from "./actions";
import { BlockPopover } from "./block-popover";
import { BlockCard, GlimpseCard, type CalendarGoal } from "./calendar-items";
import { DAY_MS, dayOffset, GUTTER, HOUR, isoAt, minutesAt, PAD, startOfDay, y } from "./geometry";

export type { CalendarGoal };
export type CalendarGroup = {
  goal: CalendarGoal;
  suggestions: { title: string; why: string; minutes: number }[];
};

/** An open task the calendar can place. */
export type CalendarTask = { id: string; goalId: string; title: string; minutes: number };

/** Something Glimpse places: a task of yours or a suggestion, with its goal. */
type Item = PlanItem & { key: string; id: string; goal: CalendarGoal };
type Result = { ok: true } | { ok: false; error: string };

const TIMELINE_HEIGHT = y(DAY_MINUTES) + PAD;

/** Temporary ids for blocks shown before the server has saved them. */
let pendingSeq = 0;
const pendingId = () => `pending-${++pendingSeq}`;
const snapDown = (m: number) => Math.floor(m / BLOCK_STEP) * BLOCK_STEP;
const snapUp = (m: number) => Math.ceil(m / BLOCK_STEP) * BLOCK_STEP;
const clamp = (m: number) => Math.min(DAY_MINUTES, Math.max(0, m));

/* The clock ticks per minute in the browser only; the server has no idea of the viewer's time. */
function subscribeClock(onChange: () => void) {
  const id = setInterval(onChange, 15_000);
  return () => clearInterval(id);
}
const minuteNow = () => Math.floor(Date.now() / 60_000);
const noClock = () => null;

/* Small per-browser preferences. Storage can be unavailable, so fall back to memory. */
const memory = new Map<string, string>();
function readPref(key: string) {
  try {
    return localStorage.getItem(key) ?? memory.get(key) ?? null;
  } catch {
    return memory.get(key) ?? null;
  }
}
function writePref(key: string, value: string) {
  memory.set(key, value);
  try {
    localStorage.setItem(key, value);
  } catch {
    // Memory still has it for this visit.
  }
}

const GLIMPSE_KEY = "sv-calendar-glimpse";
const LAST_GOAL_KEY = "sv-calendar-last-goal";
const glimpseListeners = new Set<() => void>();
function subscribeGlimpse(onChange: () => void) {
  glimpseListeners.add(onChange);
  return () => glimpseListeners.delete(onChange);
}
const readGlimpse = () => readPref(GLIMPSE_KEY) !== "off";
const serverGlimpse = () => true;
function setGlimpse(on: boolean) {
  writePref(GLIMPSE_KEY, on ? "on" : "off");
  glimpseListeners.forEach((l) => l());
}

function dayLabel(offset: number) {
  return offset === 0 ? "Today" : offset === 1 ? "Tomorrow" : offset === -1 ? "Yesterday" : null;
}

type Op =
  | { type: "add"; block: BlockView }
  | { type: "update"; id: string; patch: Partial<BlockView> }
  | { type: "remove"; id: string };

function applyOp(blocks: BlockView[], op: Op): BlockView[] {
  switch (op.type) {
    case "add":
      return [...blocks, op.block];
    case "update":
      return blocks.map((b) => (b.id === op.id ? { ...b, ...op.patch } : b));
    case "remove":
      return blocks.filter((b) => b.id !== op.id);
  }
}

/** A block cut into its parts on each day it touches (blocks rarely cross midnight). */
function segments(block: BlockView, base: Date): PlanBlock[] {
  const s = new Date(block.startsAt);
  const e = new Date(block.endsAt);
  const d0 = dayOffset(s, base);
  const d1 = dayOffset(e, base);
  const startMin = s.getHours() * 60 + s.getMinutes();
  const endMin = e.getHours() * 60 + e.getMinutes();
  const common = {
    id: block.id,
    goalId: block.goalId,
    title: block.title,
    keepOpen: block.keepOpen,
    fromSuggestion: block.fromSuggestion,
    taskId: block.taskId,
    fits: block.fits,
  };
  if (d0 === d1) return [{ ...common, day: d0, start: startMin, end: endMin }];
  const parts: PlanBlock[] = [{ ...common, day: d0, start: startMin, end: DAY_MINUTES }];
  for (let d = d0 + 1; d < d1; d++) parts.push({ ...common, day: d, start: 0, end: DAY_MINUTES });
  if (endMin > 0) parts.push({ ...common, day: d1, start: 0, end: endMin });
  return parts;
}

type Popover =
  | { mode: "create"; day: number; start: number; end: number; initial: BlockDetails }
  | { mode: "edit"; blockId: string; day: number; start: number; end: number; initial: BlockDetails; intention: boolean };

type Drag =
  | { kind: "create"; day: number; from: number; to: number; moved: boolean; originY: number }
  | {
      kind: "move";
      /** "move" drags the whole block; "start" and "end" drag its top or bottom edge. */
      edge: Edge;
      blockId: string;
      day: number;
      start: number;
      end: number;
      delta: number;
      originY: number;
      moved: boolean;
    };

type Edge = "move" | "start" | "end";

/** Where a block's edges sit while one of them, or the whole block, is being dragged. */
function dragged(edge: Edge, start: number, end: number, delta: number) {
  return { start: start + (edge === "end" ? 0 : delta), end: end + (edge === "start" ? 0 : delta) };
}

/**
 * One day, hour by hour. Intentions and protected time are yours: drag on empty
 * space to protect time, drag a block to move it, click it to edit. With Glimpse
 * on, the goals' open suggestions are placed around and inside them, from now
 * on, spilling into the following days; + commits one to its time.
 */
export function DayCalendar({
  groups,
  tasks,
  goals,
  blocks: savedBlocks,
  settings,
}: {
  groups: CalendarGroup[];
  /** Open tasks across goals, in each goal's order. */
  tasks: CalendarTask[];
  goals: CalendarGoal[];
  blocks: BlockView[];
  settings: Settings;
}) {
  const stamp = useSyncExternalStore(subscribeClock, minuteNow, noClock);
  const glimpse = useSyncExternalStore(subscribeGlimpse, readGlimpse, serverGlimpse);
  const clock = useClock(settings.clock);
  const [offset, setOffset] = useState(0);
  const [blocks, apply] = useOptimistic(savedBlocks, applyOp);
  const [popover, setPopover] = useState<Popover | null>(null);
  const [drag, setDrag] = useState<Drag | null>(null);
  const [error, setError] = useState<string | null>(null);

  const ready = stamp !== null;
  const today = ready ? new Date(stamp * 60_000) : null;
  const base = today ? startOfDay(today) : null;
  const now = today ? today.getHours() * 60 + today.getMinutes() : null;
  const isToday = offset === 0;
  const goalById = new Map(goals.map((g) => [g.id, g]));

  const allSegments = base ? blocks.flatMap((b) => segments(b, base)) : [];
  const daySegments = allSegments.filter((s) => s.day === offset);

  // Goal by goal, in the goals' order: its tasks (in your order), then its suggestions.
  const items: Item[] = goals.flatMap((goal) => [
    ...tasks
      .filter((t) => t.goalId === goal.id)
      .map((t): Item => ({ kind: "task", key: `t:${t.id}`, id: t.id, goalId: goal.id, title: t.title, minutes: t.minutes, fitKey: `t:${t.id}`, goal })),
    ...(groups.find((g) => g.goal.id === goal.id)?.suggestions ?? []).map(
      (s): Item => ({ kind: "suggestion", key: `s:${goal.id}:${s.title}`, id: s.title, goalId: goal.id, title: s.title, minutes: s.minutes, fitKey: `s:${s.title}`, goal }),
    ),
  ]);
  const placed =
    now === null || !glimpse ? [] : planDays(items, now, settings, allSegments).filter((p) => p.day === offset);
  const count = items.length;
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
      if (target?.closest("input, textarea, select, [contenteditable='true'], [data-calendar-popover], [role='menu']")) return;
      const focused = card.current?.contains(document.activeElement) ?? false;
      if (!hovered.current && !focused) return;
      e.preventDefault();
      setPopover(null);
      setOffset((o) => o + (e.key === "ArrowLeft" ? -1 : 1));
    }
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [ready]);

  function run(op: Op, action: () => Promise<Result>) {
    setError(null);
    startTransition(async () => {
      apply(op);
      const result = await action();
      if (!result.ok) setError(result.error);
    });
  }

  const closePopover = useCallback(() => setPopover(null), []);

  // --- Dragging: on empty space to protect time, on a block to move it. ---

  const timeline = useRef<HTMLDivElement>(null);
  const minuteAtPointer = (clientY: number) => {
    const rect = timeline.current!.getBoundingClientRect();
    return clamp(minutesAt(clientY - rect.top));
  };

  function onTimelineDown(e: React.PointerEvent<HTMLDivElement>) {
    if (!ready || e.button !== 0 || e.target !== e.currentTarget) return;
    const rect = e.currentTarget.getBoundingClientRect();
    if (e.clientX - rect.left < parseFloat(GUTTER) * 16) return;
    e.currentTarget.setPointerCapture(e.pointerId);
    const m = minuteAtPointer(e.clientY);
    setDrag({ kind: "create", day: offset, from: m, to: m, moved: false, originY: e.clientY });
  }

  function onBlockDown(e: React.PointerEvent<HTMLLIElement>, seg: PlanBlock) {
    const target = e.target as HTMLElement;
    if (e.button !== 0 || target.closest("button, [role='menuitem']")) return;
    e.stopPropagation();
    timeline.current?.setPointerCapture(e.pointerId);
    const edge = (target.closest("[data-edge]")?.getAttribute("data-edge") as Edge | null) ?? "move";
    setDrag({ kind: "move", edge, blockId: seg.id, day: seg.day, start: seg.start, end: seg.end, delta: 0, originY: e.clientY, moved: false });
  }

  function onPointerMove(e: React.PointerEvent<HTMLDivElement>) {
    if (!drag) return;
    const moved = drag.moved || Math.abs(e.clientY - drag.originY) > 4;
    if (drag.kind === "create") {
      setDrag({ ...drag, to: minuteAtPointer(e.clientY), moved });
    } else {
      const raw = Math.round((((e.clientY - drag.originY) / HOUR) * 60) / BLOCK_STEP) * BLOCK_STEP;
      // Keep it within the day, and at least 15 minutes long when changing its length.
      const [min, max] =
        drag.edge === "start"
          ? [-drag.start, drag.end - BLOCK_STEP - drag.start]
          : drag.edge === "end"
            ? [drag.start + BLOCK_STEP - drag.end, DAY_MINUTES - drag.end]
            : [-drag.start, DAY_MINUTES - drag.end];
      const delta = Math.max(min, Math.min(max, raw));
      setDrag({ ...drag, delta, moved });
    }
  }

  function onPointerUp() {
    if (!drag || !base) return setDrag(null);
    setDrag(null);

    if (drag.kind === "create") {
      let start: number;
      let end: number;
      if (!drag.moved) {
        start = snapDown(drag.from);
        end = Math.min(DAY_MINUTES, start + 60);
        if (end - start < BLOCK_STEP) start = end - BLOCK_STEP;
      } else {
        start = snapDown(Math.min(drag.from, drag.to));
        end = Math.max(start + BLOCK_STEP, snapUp(Math.max(drag.from, drag.to)));
      }
      const last = readPref(LAST_GOAL_KEY);
      const goalId = goals.some((g) => g.id === last) ? last! : (goals[0]?.id ?? "");
      setPopover({ mode: "create", day: drag.day, start, end, initial: { goalId, title: null, keepOpen: false } });
      return;
    }

    const block = blocks.find((b) => b.id === drag.blockId);
    if (!block) return;
    if (!drag.moved) {
      if (drag.edge !== "move") return;
      // A click: edit it.
      setPopover({
        mode: "edit",
        blockId: block.id,
        day: drag.day,
        start: drag.start,
        end: drag.end,
        intention: Boolean(block.fromSuggestion || block.taskId),
        initial: { goalId: block.goalId, title: block.title, keepOpen: block.keepOpen },
      });
      return;
    }
    if (drag.delta === 0) return;
    const shift = drag.delta * 60_000;
    const times = {
      startsAt: new Date(Date.parse(block.startsAt) + (drag.edge === "end" ? 0 : shift)).toISOString(),
      endsAt: new Date(Date.parse(block.endsAt) + (drag.edge === "start" ? 0 : shift)).toISOString(),
    };
    run({ type: "update", id: block.id, patch: times }, () => moveBlockAction(block.id, times));
  }

  // --- Saving ---

  function saveCreate(p: Extract<Popover, { mode: "create" }>, details: BlockDetails) {
    if (!base) return;
    writePref(LAST_GOAL_KEY, details.goalId);
    const times = { startsAt: isoAt(base, p.day, p.start), endsAt: isoAt(base, p.day, p.end) };
    setPopover(null);
    run(
      { type: "add", block: { id: pendingId(), ...details, ...times, fromSuggestion: null, taskId: null, taskDone: false, fits: [] } },
      () => createBlockAction({ ...details, ...times }),
    );
  }

  function saveEdit(p: Extract<Popover, { mode: "edit" }>, details: BlockDetails) {
    writePref(LAST_GOAL_KEY, details.goalId);
    setPopover(null);
    run({ type: "update", id: p.blockId, patch: details }, () => updateBlockAction(p.blockId, details));
  }

  function moveToTomorrow(block: BlockView) {
    const shift = (d: string) => {
      const date = new Date(d);
      date.setDate(date.getDate() + 1);
      return date.toISOString();
    };
    const times = { startsAt: shift(block.startsAt), endsAt: shift(block.endsAt) };
    run({ type: "update", id: block.id, patch: times }, () => moveBlockAction(block.id, times));
  }

  /** + on a glimpse: schedule the task, or turn the suggestion into a task and schedule that. */
  function addIntention(item: Item, start: number, end: number) {
    if (!base) return;
    const times = { startsAt: isoAt(base, offset, start), endsAt: isoAt(base, offset, end) };
    const isTask = item.kind === "task";
    run(
      {
        type: "add",
        block: {
          id: pendingId(),
          goalId: item.goalId,
          title: item.title,
          keepOpen: false,
          fromSuggestion: isTask ? null : item.title,
          taskId: isTask ? item.id : null,
          taskDone: false,
          fits: [],
          ...times,
        },
      },
      () => (isTask ? scheduleTaskAction(item.id, times) : createIntentionAction(item.goalId, item.title, times)),
    );
  }

  const shownDay = base ? new Date(base.getTime() + 12 * 3600_000 + offset * DAY_MS) : null;
  const relative = dayLabel(offset);
  const dayName = (day: number) =>
    base ? new Date(base.getTime() + 12 * 3600_000 + day * DAY_MS).toLocaleDateString(undefined, { weekday: "long" }) : "";

  // The draft while creating: live while dragging, then held while the popover is open.
  let draft: { start: number; end: number } | null = null;
  if (drag?.kind === "create" && drag.moved && drag.day === offset) {
    const start = snapDown(Math.min(drag.from, drag.to));
    draft = { start, end: Math.max(start + BLOCK_STEP, snapUp(Math.max(drag.from, drag.to))) };
  } else if (popover?.mode === "create" && popover.day === offset) {
    draft = { start: popover.start, end: popover.end };
  }

  const popoverBlock = popover?.mode === "edit" ? blocks.find((b) => b.id === popover.blockId) : undefined;

  return (
    <div className="flex min-h-0 flex-1 flex-col">
      {count === 0 && (
        <p className="mb-3 shrink-0 rounded-2xl border border-dashed border-foreground/15 p-4 text-sm text-muted">
          Nothing to place yet. Add tasks to a goal, or get suggestions from its status update, and they show up here.
        </p>
      )}

      <div
        ref={card}
        onPointerEnter={() => (hovered.current = true)}
        onPointerLeave={() => (hovered.current = false)}
        className="flex min-h-0 flex-1 flex-col overflow-hidden rounded-2xl border border-card-border bg-card"
      >
        {/* Day header: step between days on the left, the date beside them, Glimpse on the right. */}
        <div className="flex shrink-0 items-center gap-3 border-b border-card-border px-3 py-3 sm:px-4">
          <div className="flex shrink-0 items-center gap-1">
            <NavButton label="Previous day" icon={ArrowLeft01Icon} disabled={!ready} onClick={() => setOffset((o) => o - 1)} />
            <NavButton label="Next day" icon={ArrowRight01Icon} disabled={!ready} onClick={() => setOffset((o) => o + 1)} />
          </div>
          <h2 aria-live="polite" className="flex min-w-0 items-baseline gap-2" suppressHydrationWarning>
            <span className="truncate text-[15px] font-semibold tracking-[-0.01em] text-foreground">
              {shownDay === null
                ? "Today"
                : shownDay.toLocaleDateString(undefined, { weekday: "long", month: "long", day: "numeric" })}
            </span>
            {shownDay !== null && relative && <span className="hidden shrink-0 text-sm text-muted sm:inline">{relative}</span>}
          </h2>
          <div className="ml-auto flex shrink-0 items-center gap-1.5">
            {!isToday && (
              <button
                type="button"
                onClick={() => setOffset(0)}
                className="h-8 rounded-lg border border-card-border bg-card px-3 text-sm font-medium text-foreground shadow-[0_1px_2px_rgb(15_17_20/0.05)] transition-colors hover:border-line-strong"
              >
                Today
              </button>
            )}
            <button
              type="button"
              aria-pressed={glimpse}
              onClick={() => setGlimpse(!glimpse)}
              title={glimpse ? "Hide suggestions" : "Show suggestions"}
              className={`flex h-8 items-center gap-1.5 rounded-lg border px-2.5 text-sm font-medium transition-colors ${
                glimpse
                  ? "border-line-strong bg-foreground/[.06] text-foreground"
                  : "border-card-border bg-card text-muted shadow-[0_1px_2px_rgb(15_17_20/0.05)] hover:border-line-strong hover:text-foreground"
              }`}
            >
              <HugeiconsIcon icon={glimpse ? ViewIcon : ViewOffIcon} size={15} />
              Glimpse
            </button>
          </div>
        </div>

        {error && (
          <p role="alert" className="shrink-0 border-b border-card-border px-4 py-2 text-sm text-red-600 dark:text-red-400">
            {error}
          </p>
        )}

        <div
          ref={scroller}
          tabIndex={0}
          aria-label="Day timeline. Drag on empty space to protect time. Use the left and right arrow keys to change day."
          className="min-h-0 flex-1 overflow-y-auto overscroll-contain outline-none focus-visible:outline-2 focus-visible:-outline-offset-2 focus-visible:outline-foreground/20"
        >
          <div
            ref={timeline}
            onPointerDown={onTimelineDown}
            onPointerMove={onPointerMove}
            onPointerUp={onPointerUp}
            onPointerCancel={() => setDrag(null)}
            className={`relative select-none ${drag?.kind === "create" || (drag?.kind === "move" && drag.edge !== "move") ? "cursor-ns-resize" : ""}`}
            style={{ height: TIMELINE_HEIGHT }}
          >
            {/* Hour lines and labels */}
            {Array.from({ length: 25 }, (_, h) => {
              const nearNow = isToday && now !== null && Math.abs(h * 60 - now) < 14;
              return (
                <div key={h} className="pointer-events-none absolute inset-x-0" style={{ top: y(h * 60) }}>
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
                className="pointer-events-none absolute right-0 bg-[repeating-linear-gradient(135deg,color-mix(in_oklab,var(--foreground)_6%,transparent)_0_1px,transparent_1px_7px)]"
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
                className="pointer-events-none absolute right-0 bg-foreground/[.03]"
                style={{ left: GUTTER, top: PAD, height: y(pastUntil) - PAD }}
              />
            )}

            {/* Your intentions and protected time */}
            {daySegments.length > 0 && (
              <ul aria-label="Your time on this day">
                {daySegments.map((seg) => {
                  const block = blocks.find((b) => b.id === seg.id)!;
                  const moving = drag?.kind === "move" && drag.blockId === seg.id && drag.moved;
                  const at = moving ? dragged(drag.edge, seg.start, seg.end, drag.delta) : seg;
                  return (
                    <BlockCard
                      key={`${seg.id}:${seg.day}`}
                      block={block}
                      goal={goalById.get(block.goalId)}
                      start={at.start}
                      end={at.end}
                      clock={clock}
                      pending={block.id.startsWith("pending-")}
                      dragging={moving}
                      onPointerDown={(e) => onBlockDown(e, seg)}
                      onEdit={() =>
                        setPopover({
                          mode: "edit",
                          blockId: block.id,
                          day: seg.day,
                          start: seg.start,
                          end: seg.end,
                          intention: Boolean(block.fromSuggestion || block.taskId),
                          initial: { goalId: block.goalId, title: block.title, keepOpen: block.keepOpen },
                        })
                      }
                      onTomorrow={() => moveToTomorrow(block)}
                      onToggleDone={
                        block.taskId
                          ? () =>
                              run({ type: "update", id: block.id, patch: { taskDone: !block.taskDone } }, () =>
                                setBlockTaskDoneAction(block.id, !block.taskDone),
                              )
                          : undefined
                      }
                      onRemove={() => run({ type: "remove", id: block.id }, () => deleteBlockAction(block.id))}
                    />
                  );
                })}
              </ul>
            )}

            {/* Glimpse: your open tasks and suggestions, not yet committed to a time */}
            {placed.length > 0 && (
              <ol aria-label="Glimpse: tasks and suggestions on this day">
                {placed.map(({ item, start, end, blockId }) => (
                  <GlimpseCard
                    key={item.key}
                    kind={item.kind}
                    title={item.title}
                    goal={item.goal}
                    start={start}
                    end={end}
                    clock={clock}
                    inBlock={blockId !== null}
                    onAdd={() => addIntention(item, start, end)}
                  />
                ))}
              </ol>
            )}

            {/* The block being drawn */}
            {draft && (
              <div
                aria-hidden="true"
                className="pointer-events-none absolute z-30 rounded-lg border-2 border-dashed border-foreground/40 bg-foreground/[.04]"
                style={{ top: y(draft.start) + 1, height: y(draft.end) - y(draft.start) - 2, left: `calc(${GUTTER} + 4px)`, right: 8 }}
              >
                <span className="absolute left-3 top-1.5 text-[11px] font-medium tabular-nums text-muted">
                  {formatRange(draft.start, draft.end, clock)}
                </span>
              </div>
            )}

            {/* Now */}
            {isToday && now !== null && (
              <div className="pointer-events-none absolute inset-x-0 z-30" style={{ top: y(now) }}>
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

            {popover && popover.day === offset && (popover.mode === "create" || popoverBlock) && (
              <BlockPopover
                key={popover.mode === "edit" ? popover.blockId : `new-${popover.start}`}
                anchorTop={y(popover.start)}
                anchorBottom={y(popover.end)}
                timelineHeight={TIMELINE_HEIGHT}
                goals={goals}
                initial={popover.initial}
                intention={popover.mode === "edit" && popover.intention}
                timeLabel={`${dayName(popover.day)} · ${formatRange(popover.start, popover.end, clock)}`}
                onCancel={closePopover}
                onSave={(details) => (popover.mode === "create" ? saveCreate(popover, details) : saveEdit(popover, details))}
              />
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
