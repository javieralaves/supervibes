"use client";

import { ArrowLeft01Icon, ArrowRight01Icon, CheckListIcon, CircleIcon, Moon02Icon, ViewIcon, ViewOffIcon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon, type IconSvgElement } from "@hugeicons/react";
import {
  startTransition,
  useCallback,
  useEffect,
  useEffectEvent,
  useOptimistic,
  useRef,
  useState,
  useSyncExternalStore,
} from "react";

import type { BlockDetails, BlockView } from "@/lib/block-schema";
import { BLOCK_STEP } from "@/lib/block-schema";
import { formatHour, formatRange, formatTime, useClock } from "@/lib/clock";
import { goalColorStyle } from "@/lib/goal-colors";
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
import { BlockPanel } from "./block-panel";
import { BlockPopover } from "./block-popover";
import { BlockCard, DropPreview, GlimpseCard, type CalendarGoal } from "./calendar-items";
import { DAY_MS, dayOffset, GUTTER, HOUR, isoAt, minutesAt, PAD, startOfDay, y } from "./geometry";
import { TaskPanel, type PanelGroup, type PanelTask } from "./task-panel";

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
const TASK_PANEL_KEY = "sv-calendar-task-panel";
const LAST_GOAL_KEY = "sv-calendar-last-goal";
const prefListeners = new Set<() => void>();
function subscribePrefs(onChange: () => void) {
  prefListeners.add(onChange);
  return () => prefListeners.delete(onChange);
}
const readGlimpse = () => readPref(GLIMPSE_KEY) !== "off";
const serverGlimpse = () => true;
function setGlimpse(on: boolean) {
  writePref(GLIMPSE_KEY, on ? "on" : "off");
  prefListeners.forEach((l) => l());
}
const readTaskPanel = () => readPref(TASK_PANEL_KEY) === "on";
const serverTaskPanel = () => false;
function setTaskPanel(on: boolean) {
  writePref(TASK_PANEL_KEY, on ? "on" : "off");
  prefListeners.forEach((l) => l());
}

/** Header toggles (Tasks, Glimpse): pressed or not. */
const toggleClass = (on: boolean) =>
  on
    ? "border-line-strong bg-foreground/[.06] text-foreground"
    : "border-card-border bg-card text-muted shadow-[0_1px_2px_rgb(15_17_20/0.05)] hover:border-line-strong hover:text-foreground";

/** How close to the timeline's top or bottom edge a dragged task starts it scrolling, in px. */
const SCROLL_EDGE = 56;

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

/** A task being dragged from the panel onto the day. */
type Placing = {
  task: PanelTask;
  /** How long it lands: its block's length when it has one, else its estimate. */
  minutes: number;
  originX: number;
  originY: number;
  /** Past the few pixels that tell a drag from a click. */
  moved: boolean;
  /** Where the pointer was when it started moving, so the chip appears there. */
  x: number;
  y: number;
  /** Where it would land on the shown day, or null while the pointer is off the timeline. */
  start: number | null;
};

/** Where a block's edges sit while one of them, or the whole block, is being dragged. */
function dragged(edge: Edge, start: number, end: number, delta: number) {
  return { start: start + (edge === "end" ? 0 : delta), end: end + (edge === "start" ? 0 : delta) };
}

/**
 * One day, hour by hour. Intentions and protected time are yours: drag on empty
 * space to protect time, drag a block to move it, click it to edit. With Glimpse
 * on, your open tasks are placed inside and around them, and suggestions inside
 * their goal's protected time only, from now on, spilling into the following
 * days; + commits one to its time. The task
 * panel lists open tasks across goals; drag one onto the day to schedule it.
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
  const glimpse = useSyncExternalStore(subscribePrefs, readGlimpse, serverGlimpse);
  const taskPanel = useSyncExternalStore(subscribePrefs, readTaskPanel, serverTaskPanel);
  const clock = useClock(settings.clock);
  const [offset, setOffset] = useState(0);
  const [blocks, apply] = useOptimistic(savedBlocks, applyOp);
  const [popover, setPopover] = useState<Popover | null>(null);
  const [drag, setDrag] = useState<Drag | null>(null);
  const [placing, setPlacing] = useState<Placing | null>(null);
  /** The block whose panel is open on the right. */
  const [selectedId, setSelectedId] = useState<string | null>(null);
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
  const plan = now === null || (!glimpse && !taskPanel) ? [] : planDays(items, now, settings, allSegments);
  const placed = glimpse ? plan.filter((p) => p.day === offset) : [];
  const count = items.length;
  // Earlier days are all behind you; later days haven't started.
  const pastUntil = offset < 0 ? DAY_MINUTES : isToday ? now : null;

  // The panel: each goal's open tasks in your order, those already on the calendar last.
  let panelGroups: PanelGroup[] = [];
  if (taskPanel) {
    const nowMs = today?.getTime() ?? 0;
    const nextBlock = new Map<string, BlockView>();
    for (const b of blocks) {
      if (!b.taskId || Date.parse(b.endsAt) <= nowMs) continue;
      const seen = nextBlock.get(b.taskId);
      if (!seen || Date.parse(b.startsAt) < Date.parse(seen.startsAt)) nextBlock.set(b.taskId, b);
    }
    const spots = new Map(plan.filter((p) => p.item.kind === "task").map((p) => [p.item.id, p]));
    panelGroups = goals
      .map((goal) => {
        const mine = tasks
          .filter((t) => t.goalId === goal.id)
          .map((t): PanelTask => {
            const block = nextBlock.get(t.id) ?? null;
            const spot = block ? undefined : spots.get(t.id);
            return { ...t, block, spot: spot ? { day: spot.day, start: spot.start, end: spot.end } : null };
          });
        return { goal, tasks: [...mine.filter((t) => !t.block), ...mine.filter((t) => t.block)] };
      })
      .filter((g) => g.tasks.length > 0);
  }

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

  /** Open a block's panel. Below the width the panel needs, edit it in place instead. */
  function openBlockPanel(blockId: string) {
    const block = blocks.find((b) => b.id === blockId);
    if (!block || block.id.startsWith("pending-")) return;
    if (window.matchMedia("(min-width: 64rem)").matches) {
      setPopover(null);
      setSelectedId(block.id);
    } else {
      editBlock(block);
    }
  }

  /** Open the edit popover on a block, stepping to its day first if it's on another one. */
  function editBlock(block: BlockView) {
    const seg = allSegments.find((s) => s.id === block.id && s.day === offset) ?? allSegments.find((s) => s.id === block.id);
    if (!seg) return;
    if (seg.day !== offset) setOffset(seg.day);
    setPopover({
      mode: "edit",
      blockId: block.id,
      day: seg.day,
      start: seg.start,
      end: seg.end,
      intention: Boolean(block.fromSuggestion || block.taskId),
      initial: { goalId: block.goalId, title: block.title, keepOpen: block.keepOpen },
    });
  }

  // Esc closes the block panel, unless something else (the popover, a drag) took it.
  const closePanelOnEscape = useEffectEvent((e: KeyboardEvent) => {
    if (e.key !== "Escape" || e.defaultPrevented || popover || placing) return;
    const target = e.target as HTMLElement | null;
    if (target?.closest("input, textarea, select, [contenteditable='true'], [role='menu']")) return;
    setSelectedId(null);
  });
  const panelOpen = selectedId !== null;
  useEffect(() => {
    if (!panelOpen) return;
    const onKey = (e: KeyboardEvent) => closePanelOnEscape(e);
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [panelOpen]);

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
      // A click: open its panel. Below the width the panel needs, edit it in place as before.
      if (window.matchMedia("(min-width: 64rem)").matches) {
        setPopover(null);
        setSelectedId(block.id);
        return;
      }
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

  // --- Placing: dragging a task from the panel onto the day. ---

  const pointer = useRef({ x: 0, y: 0 });
  const chip = useRef<HTMLDivElement>(null);
  const placingActive = placing !== null;

  function onTaskPointerDown(e: React.PointerEvent<HTMLElement>, task: PanelTask) {
    if (!ready || e.button !== 0 || (e.target as HTMLElement).closest("button")) return;
    e.preventDefault();
    pointer.current = { x: e.clientX, y: e.clientY };
    setPopover(null);
    const minutes = task.block
      ? Math.min(DAY_MINUTES, Math.round((Date.parse(task.block.endsAt) - Date.parse(task.block.startsAt)) / 60_000))
      : task.minutes;
    setPlacing({ task, minutes, originX: e.clientX, originY: e.clientY, moved: false, x: e.clientX, y: e.clientY, start: null });
  }

  /** The start a dragged task would get on the shown day, or null while the pointer is off the timeline. */
  const landing = useEffectEvent((): number | null => {
    const view = scroller.current?.getBoundingClientRect();
    const rect = timeline.current?.getBoundingClientRect();
    if (!placing || !view || !rect) return null;
    const { x, y: py } = pointer.current;
    if (x < rect.left + parseFloat(GUTTER) * 16 || x > view.right || py < view.top || py > view.bottom) return null;
    return Math.max(0, Math.min(DAY_MINUTES - placing.minutes, snapDown(minutesAt(py - rect.top))));
  });

  /** Every frame while dragging: scroll near the timeline's edges, move the chip, update where it lands. */
  const followPointer = useEffectEvent(() => {
    if (!placing) return;
    const { x, y: py } = pointer.current;
    const sc = scroller.current;
    if (placing.moved && sc) {
      const view = sc.getBoundingClientRect();
      if (x >= view.left && x <= view.right) {
        const above = view.top + SCROLL_EDGE - py;
        const below = py - (view.bottom - SCROLL_EDGE);
        if (above > 0 && above < SCROLL_EDGE * 2) sc.scrollTop -= Math.min(18, Math.ceil(above / 4));
        else if (below > 0 && below < SCROLL_EDGE * 2) sc.scrollTop += Math.min(18, Math.ceil(below / 4));
      }
    }
    if (chip.current) chip.current.style.transform = `translate(${x + 14}px, ${py + 10}px)`;
    const start = placing.moved ? landing() : null;
    if (start !== placing.start) setPlacing({ ...placing, start });
  });

  const onPlacingMove = useEffectEvent((e: PointerEvent) => {
    pointer.current = { x: e.clientX, y: e.clientY };
    if (placing && !placing.moved && Math.hypot(e.clientX - placing.originX, e.clientY - placing.originY) > 4) {
      setPlacing({ ...placing, moved: true, x: e.clientX, y: e.clientY });
    }
  });

  /** Let go: schedule the task at that time, or move its block there. Anywhere else, nothing happens. */
  const dropPlacing = useEffectEvent(() => {
    const p = placing;
    const start = landing();
    setPlacing(null);
    if (!p?.moved || start === null || !base) return;
    const times = { startsAt: isoAt(base, offset, start), endsAt: isoAt(base, offset, start + p.minutes) };
    const block = p.task.block;
    if (!block) return scheduleTask(p.task, times);
    if (Date.parse(block.startsAt) === Date.parse(times.startsAt)) return;
    run({ type: "update", id: block.id, patch: times }, () => moveBlockAction(block.id, times));
  });

  useEffect(() => {
    if (!placingActive) return;
    let frame = requestAnimationFrame(function tick() {
      followPointer();
      frame = requestAnimationFrame(tick);
    });
    const onMove = (e: PointerEvent) => onPlacingMove(e);
    const onUp = () => dropPlacing();
    const onCancel = () => setPlacing(null);
    const onKey = (e: KeyboardEvent) => {
      if (e.key !== "Escape") return;
      e.preventDefault();
      setPlacing(null);
    };
    const cursor = document.body.style.cursor;
    document.body.style.cursor = "grabbing";
    window.addEventListener("pointermove", onMove);
    window.addEventListener("pointerup", onUp);
    window.addEventListener("pointercancel", onCancel);
    window.addEventListener("keydown", onKey);
    return () => {
      cancelAnimationFrame(frame);
      document.body.style.cursor = cursor;
      window.removeEventListener("pointermove", onMove);
      window.removeEventListener("pointerup", onUp);
      window.removeEventListener("pointercancel", onCancel);
      window.removeEventListener("keydown", onKey);
    };
  }, [placingActive]);

  // --- Saving ---

  function saveCreate(p: Extract<Popover, { mode: "create" }>, details: BlockDetails) {
    if (!base) return;
    writePref(LAST_GOAL_KEY, details.goalId);
    const times = { startsAt: isoAt(base, p.day, p.start), endsAt: isoAt(base, p.day, p.end) };
    setPopover(null);
    run(
      { type: "add", block: { id: pendingId(), ...details, ...times, fromSuggestion: null, taskId: null, taskDone: false, fits: [], agenda: null } },
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

  /** Put one of your tasks on the calendar at these times. */
  function scheduleTask(task: { id: string; goalId: string; title: string }, times: { startsAt: string; endsAt: string }) {
    run(
      {
        type: "add",
        block: {
          id: pendingId(),
          goalId: task.goalId,
          title: task.title,
          keepOpen: false,
          fromSuggestion: null,
          taskId: task.id,
          taskDone: false,
          fits: [],
          agenda: null,
          ...times,
        },
      },
      () => scheduleTaskAction(task.id, times),
    );
  }

  /** + on a glimpse: schedule the task, or turn the suggestion into a task and schedule that. */
  function addIntention(item: Item, start: number, end: number) {
    if (!base) return;
    const times = { startsAt: isoAt(base, offset, start), endsAt: isoAt(base, offset, end) };
    if (item.kind === "task") return scheduleTask(item, times);
    run(
      {
        type: "add",
        block: {
          id: pendingId(),
          goalId: item.goalId,
          title: item.title,
          keepOpen: false,
          fromSuggestion: item.title,
          taskId: null,
          taskDone: false,
          fits: [],
          agenda: null,
          ...times,
        },
      },
      () => createIntentionAction(item.goalId, item.title, times),
    );
  }

  /** + in the task panel: schedule it where Glimpse would put it. */
  function scheduleAtSpot(task: PanelTask) {
    if (!base || !task.spot) return;
    const { day, start, end } = task.spot;
    scheduleTask(task, { startsAt: isoAt(base, day, start), endsAt: isoAt(base, day, end) });
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

  // The block panel: hidden while the block is still being saved, or once it's gone.
  const selected = selectedId && !selectedId.startsWith("pending-") ? blocks.find((b) => b.id === selectedId) : undefined;
  const openTaskIds = new Set(tasks.map((t) => t.id));
  let selectedTimes: { label: string; when: string } | null = null;
  if (selected && base) {
    const s = new Date(selected.startsAt);
    const e = new Date(selected.endsAt);
    const startMin = s.getHours() * 60 + s.getMinutes();
    const endMin = dayOffset(e, base) > dayOffset(s, base) ? DAY_MINUTES : e.getHours() * 60 + e.getMinutes();
    const range = formatRange(startMin, endMin, clock);
    const relativeDay = dayLabel(dayOffset(s, base));
    const date = s.toLocaleDateString(undefined, { weekday: "long", month: "long", day: "numeric" });
    selectedTimes = {
      label: `${relativeDay ?? s.toLocaleDateString(undefined, { weekday: "long", month: "short", day: "numeric" })} · ${range}`,
      when: `${date}${relativeDay ? ` (${relativeDay.toLowerCase()})` : ""}, ${range}`,
    };
  }

  return (
    <div
      ref={card}
      onPointerEnter={() => (hovered.current = true)}
      onPointerLeave={() => (hovered.current = false)}
      className="flex min-h-0 flex-1 flex-col"
    >
      {/* Top bar, across the page: the task panel's toggle, then stepping between days and the date; Glimpse on the right. */}
      <header className="flex h-14 shrink-0 items-center gap-3 bg-background px-4 shadow-[inset_0_-1px_0_var(--card-border)] sm:px-6">
        <button
          type="button"
          aria-label="Tasks"
          aria-pressed={taskPanel}
          onClick={() => setTaskPanel(!taskPanel)}
          title={taskPanel ? "Hide tasks" : "Show tasks to drag onto the day"}
          className={`hidden h-8 w-8 shrink-0 items-center justify-center rounded-lg border transition-colors lg:flex ${toggleClass(taskPanel)}`}
        >
          <HugeiconsIcon icon={CheckListIcon} size={16} />
        </button>
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
            className={`flex h-8 items-center gap-1.5 rounded-lg border px-2.5 text-sm font-medium transition-colors ${toggleClass(glimpse)}`}
          >
            <HugeiconsIcon icon={glimpse ? ViewIcon : ViewOffIcon} size={15} />
            Glimpse
          </button>
        </div>
      </header>

      <div
        className={`mx-auto flex min-h-0 w-full flex-1 flex-col px-4 py-4 sm:px-8 sm:py-6 ${
          taskPanel && selected
            ? "max-w-3xl lg:max-w-[88rem]"
            : taskPanel
              ? "max-w-3xl lg:max-w-[67rem]"
              : selected
                ? "max-w-3xl lg:max-w-[69rem]"
                : "max-w-3xl"
        }`}
      >
        {count === 0 && (
          <p className="mb-3 shrink-0 rounded-2xl border border-dashed border-foreground/15 p-4 text-sm text-muted">
            Nothing to place yet. Add tasks to a goal, or get suggestions from its status update, and they show up here.
          </p>
        )}

        <div className="flex min-h-0 flex-1 gap-4">
          {taskPanel && (
            <TaskPanel
              groups={panelGroups}
              clock={clock}
              today={base}
              draggingId={placing?.moved ? placing.task.id : null}
              onTaskPointerDown={onTaskPointerDown}
              onSchedule={scheduleAtSpot}
            />
          )}

          <div
            className="flex min-h-0 min-w-0 flex-1 flex-col overflow-hidden rounded-2xl border border-card-border bg-card"
          >
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
                          selected={block.id === selected?.id}
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
                        onOpenBlock={blockId ? () => openBlockPanel(blockId) : undefined}
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

                {/* Where a task dragged from the panel would land */}
                {placing?.moved && placing.start !== null && (
                  <DropPreview
                    title={placing.task.title}
                    goal={goalById.get(placing.task.goalId)}
                    start={placing.start}
                    end={placing.start + placing.minutes}
                    clock={clock}
                  />
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

          {selected && (
            <BlockPanel
              key={selected.id}
              block={selected}
              goal={goalById.get(selected.goalId)}
              timeLabel={selectedTimes?.label ?? ""}
              when={selectedTimes?.when ?? ""}
              openTaskIds={openTaskIds}
              onEdit={() => editBlock(selected)}
              onClose={() => setSelectedId(null)}
              onToggleDone={
                selected.taskId
                  ? () =>
                      run({ type: "update", id: selected.id, patch: { taskDone: !selected.taskDone } }, () =>
                        setBlockTaskDoneAction(selected.id, !selected.taskDone),
                      )
                  : undefined
              }
            />
          )}
        </div>
      </div>


      {/* The task under the pointer while it's dragged outside the timeline */}
      {placing?.moved && (
        <div
          ref={chip}
          aria-hidden="true"
          style={{ ...goalColorStyle(goalById.get(placing.task.goalId)?.color ?? "slate"), transform: `translate(${placing.x + 14}px, ${placing.y + 10}px)` }}
          className={`pointer-events-none fixed left-0 top-0 z-50 flex max-w-60 items-center gap-1.5 rounded-lg border border-card-border bg-card px-2.5 py-1.5 shadow-[0_6px_16px_rgb(15_17_20/0.14)] transition-opacity ${
            placing.start !== null ? "opacity-0" : ""
          }`}
        >
          <HugeiconsIcon icon={CircleIcon} size={13} className="shrink-0 text-[var(--goal-light)] dark:text-[var(--goal-dark)]" />
          <span className="truncate text-[13px] font-medium text-foreground">{placing.task.title}</span>
        </div>
      )}
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
