"use client";

import {
  Add01Icon,
  Calendar03Icon,
  Cancel01Icon,
  Clock01Icon,
  DashedLineCircleIcon,
  Delete02Icon,
  DragDropVerticalIcon,
  Refresh01Icon,
  Tick02Icon,
  ViewIcon,
} from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import * as DropdownMenu from "@radix-ui/react-dropdown-menu";
import { startTransition, useEffect, useId, useLayoutEffect, useOptimistic, useRef, useState } from "react";

import { DayPill } from "@/components/day-pill";
import { MoreMenu, MoreMenuItem } from "@/components/more-menu";
import { formatTime, useClock } from "@/lib/clock";
import type { Clock } from "@/lib/settings-schema";
import {
  DEFAULT_TASK_MINUTES,
  MAX_TASK_DESCRIPTION,
  MAX_TASK_TITLE,
  minutesLabel,
  TASK_MINUTES,
  taskDescriptionSchema,
  taskTitleSchema,
} from "@/lib/task-schema";

import {
  addSuggestionAsTaskAction,
  addTaskAction,
  deleteTaskAction,
  editTaskAction,
  passOnSuggestionAction,
  reorderTasksAction,
  setTaskDoneAction,
  type ActionResult,
} from "./actions";

export type TaskView = {
  id: string;
  title: string;
  description: string | null;
  minutes: number;
  doneAt: string | null;
  /** The day they mean to do it, "YYYY-MM-DD", if they've picked one. */
  plannedFor: string | null;
  /** The day it's due, "YYYY-MM-DD", if it has a deadline. */
  dueOn: string | null;
  /** When it's next on the calendar, if it is. */
  scheduledAt?: string | null;
};
export type SuggestionView = { title: string; why: string; minutes: number };

type Op =
  | { type: "add"; task: TaskView }
  | { type: "edit"; id: string; patch: Partial<TaskView> }
  | { type: "remove"; id: string };

function applyOp(tasks: TaskView[], op: Op): TaskView[] {
  switch (op.type) {
    case "add":
      return [...tasks, op.task];
    case "edit":
      return tasks.map((t) => (t.id === op.id ? { ...t, ...op.patch } : t));
    case "remove":
      return tasks.filter((t) => t.id !== op.id);
  }
}

/** Tasks with the given ids first, in that order; the rest (done ones, new ones) after. */
function inOrder(tasks: TaskView[], ids: string[]): TaskView[] {
  const byId = new Map(tasks.map((t) => [t.id, t]));
  const ordered = ids.flatMap((id) => byId.get(id) ?? []);
  const placed = new Set(ids);
  return [...ordered, ...tasks.filter((t) => !placed.has(t.id))];
}

/** How long a dropped or moved row takes to settle into its place. */
const SETTLE_MS = 180;

/** A task being dragged: where it started and would land among the open tasks, and how far it's moved. */
type Drag = { id: string; from: number; to: number; dy: number; /** How far the rows it passes slide to make room. */ shift: number };

/** How far the pointer moves before a press on a row becomes a drag rather than a click. */
const DRAG_THRESHOLD = 4;

/** Where a row sits while a task is dragged: the dragged one follows the pointer, the ones it passes slide aside. */
function dragOffset(drag: Drag | null, index: number, id: string): number {
  if (!drag) return 0;
  if (id === drag.id) return drag.dy;
  if (drag.from < drag.to && index > drag.from && index <= drag.to) return -drag.shift;
  if (drag.to < drag.from && index >= drag.to && index < drag.from) return drag.shift;
  return 0;
}

/** The task open for editing, with what's been typed so far. */
type Draft = { id: string; title: string; description: string };

let pendingSeq = 0;

/** Same type as a task title, so things beside it can centre on its first line. */
const LINE = "text-[0.95rem] leading-snug";
/** A task's description, the same whether shown under a closed row or being edited. */
const DESCRIPTION = "mt-0.5 text-sm text-muted [overflow-wrap:anywhere]";

/** The time pill, as on suggestions. */
const PILL =
  "inline-flex w-fit items-center gap-1 rounded-full border border-card-border px-2 py-0.5 text-[11px] font-medium tabular-nums text-muted";

/**
 * A goal's open tasks. Click one to open it in place and add a description;
 * it saves when it closes (click elsewhere, Esc, or open another). Drag a row
 * (or its grip, on touch screens) to reorder, or press ⌥↑ / ⌥↓ on it. The order
 * is the person's priority: reads, agendas and the calendar follow it.
 * Checked-off tasks move to the goal's Activity.
 *
 * Each task can be planned for a day (without a time yet) and given a due date,
 * from pills beside its estimate. Empty ones show on hover and in the open task.
 *
 * Under the list, the latest read's suggestions: candidates you can add as tasks
 * or pass on. Once they're all handled, you can ask for new ones.
 */
export function TasksSection({
  goalId,
  tasks,
  suggestions,
  hasRead,
  reading,
  onRefresh,
  clock: clockPreference,
  today,
}: {
  goalId: string;
  tasks: TaskView[];
  suggestions: SuggestionView[];
  /** Whether the goal has a read yet; before the first one there's nothing to suggest. */
  hasRead: boolean;
  /** A read is in progress. */
  reading: boolean;
  /** Runs a new read, which brings new suggestions. */
  onRefresh: () => void;
  clock: Clock | null;
  /** The person's today, "YYYY-MM-DD", for the plan and due pills. */
  today: string;
}) {
  const clock = useClock(clockPreference);
  const [list, apply] = useOptimistic(tasks, applyOp);
  const [shown, hide] = useOptimistic(suggestions, (all: SuggestionView[], title: string) =>
    all.filter((s) => s.title !== title),
  );
  const [newTitle, setNewTitle] = useState("");
  const [draft, setDraft] = useState<Draft | null>(null);
  const [error, setError] = useState<string | null>(null);
  const inputId = useId();

  /*
   * A new order, shown at once, until the page's tasks come back from the server with it saved.
   * Plain state rather than an optimistic update: those (and anything else set in the same
   * transition) only commit once the save finishes, so the drop would lag a round trip.
   */
  const [localOrder, setLocalOrder] = useState<{ ids: string[]; base: TaskView[] } | null>(null);
  const ordered = localOrder && localOrder.base === tasks ? inOrder(list, localOrder.ids) : list;

  const open = ordered.filter((t) => !t.doneAt);
  const [drag, setDrag] = useState<Drag | null>(null);
  const [announcement, setAnnouncement] = useState("");
  const listRef = useRef<HTMLUListElement>(null);
  /** A task moved from the keyboard, to keep focus on once the list re-renders. */
  const refocus = useRef<string | null>(null);
  /** Where each row was on screen just before a drop or move, so it can glide to its new place. */
  const settleFrom = useRef<Map<string, number> | null>(null);
  // Not while a task is open for editing, or while a new one is still saving (its id isn't real yet).
  const canReorder = !draft && open.length > 1 && !open.some((t) => t.id.startsWith("pending-"));
  // The list is a flex column, not a grid: grid rows would widen to fit a long description line.

  function run(op: Op, action: () => Promise<ActionResult>) {
    setError(null);
    startTransition(async () => {
      apply(op);
      const result = await action();
      if (!result.ok) setError(result.error);
    });
  }

  function addSuggestion(s: SuggestionView) {
    setError(null);
    startTransition(async () => {
      hide(s.title);
      apply({
        type: "add",
        task: { id: `pending-${++pendingSeq}`, title: s.title, description: s.why || null, minutes: s.minutes, doneAt: null, plannedFor: null, dueOn: null },
      });
      const result = await addSuggestionAsTaskAction(goalId, s.title);
      if (!result.ok) setError(result.error);
    });
  }

  function passOn(s: SuggestionView) {
    setError(null);
    startTransition(async () => {
      hide(s.title);
      const result = await passOnSuggestionAction(goalId, s.title);
      if (!result.ok) setError(result.error);
    });
  }

  function add() {
    const parsed = taskTitleSchema.safeParse(newTitle);
    if (!parsed.success) return;
    setNewTitle("");
    run(
      {
        type: "add",
        task: {
          id: `pending-${++pendingSeq}`,
          title: parsed.data,
          description: null,
          minutes: DEFAULT_TASK_MINUTES,
          doneAt: null,
          plannedFor: null,
          dueOn: null,
        },
      },
      () => addTaskAction(goalId, parsed.data),
    );
  }

  /** Notes where every row is on screen now, for the next render to animate from. */
  function measureRows() {
    const tops = new Map<string, number>();
    listRef.current?.querySelectorAll<HTMLElement>("[data-task-row]").forEach((r) => {
      tops.set(r.dataset.taskRow!, r.getBoundingClientRect().top);
    });
    settleFrom.current = tops;
  }

  /** Shows the new order at once and saves it in the background. */
  function reorder(ids: string[], movedId: string) {
    const to = ids.indexOf(movedId);
    const title = open.find((t) => t.id === movedId)?.title ?? "Task";
    setAnnouncement(`${title} moved to position ${to + 1} of ${ids.length}.`);
    setError(null);
    measureRows();
    // Same render: the drag ends and the new order lands together, so nothing jumps.
    setDrag(null);
    setLocalOrder({ ids, base: tasks });
    startTransition(async () => {
      const result = await reorderTasksAction(goalId, ids);
      if (!result.ok) {
        setError(result.error);
        setLocalOrder(null);
      }
    });
  }

  /** ⌥↑ / ⌥↓ on a task: one place up or down. */
  function moveBy(id: string, by: -1 | 1) {
    if (!canReorder) return;
    const ids = open.map((t) => t.id);
    const from = ids.indexOf(id);
    const to = from + by;
    if (from < 0 || to < 0 || to >= ids.length) return;
    ids.splice(to, 0, ...ids.splice(from, 1));
    refocus.current = id;
    reorder(ids, id);
  }

  // After a drop or move: each row glides from where it was to where it now is (FLIP),
  // and a task moved from the keyboard keeps focus, which moving it in the DOM can drop.
  useLayoutEffect(() => {
    const from = settleFrom.current;
    if (from) {
      settleFrom.current = null;
      const reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
      listRef.current?.querySelectorAll<HTMLElement>("[data-task-row]").forEach((r) => {
        const before = from.get(r.dataset.taskRow!);
        const delta = before === undefined ? 0 : before - r.getBoundingClientRect().top;
        if (reduce || Math.abs(delta) < 1) return;
        r.animate([{ transform: `translateY(${delta}px)` }, { transform: "translateY(0)" }], {
          duration: SETTLE_MS,
          easing: "cubic-bezier(0.2, 0, 0, 1)",
        });
      });
    }
    const id = refocus.current;
    if (id) {
      refocus.current = null;
      listRef.current?.querySelector<HTMLElement>(`[data-task-row="${id}"] [data-task-open]`)?.focus();
    }
  });

  /**
   * A press on a row: past a few pixels it becomes a drag. With a mouse, anywhere on the
   * row but its controls; on touch screens, only the grip, so the list still scrolls.
   */
  function startDrag(e: React.PointerEvent<HTMLLIElement>, id: string) {
    if (!canReorder || e.button !== 0 || !e.isPrimary) return;
    const target = e.target as Element;
    if (target.closest('[role="checkbox"], [aria-haspopup], [role="menu"]')) return;
    if (e.pointerType !== "mouse" && !target.closest("[data-task-grip]")) return;

    const rows = [...(listRef.current?.querySelectorAll<HTMLElement>("[data-task-row]") ?? [])];
    const from = rows.findIndex((r) => r.dataset.taskRow === id);
    if (from < 0) return;
    // Page coordinates, so scrolling the page mid-drag doesn't throw the positions off.
    const boxes = rows.map((r) => {
      const b = r.getBoundingClientRect();
      return { top: b.top + window.scrollY, height: b.height };
    });
    const gap = boxes.length > 1 ? boxes[1].top - (boxes[0].top + boxes[0].height) : 0;
    const shift = boxes[from].height + gap;
    const center = boxes[from].top + boxes[from].height / 2;
    const ids = open.map((t) => t.id);
    const startY = e.pageY;
    const pointerId = e.pointerId;
    let started = false;
    let to = from;

    function onMove(ev: PointerEvent) {
      if (ev.pointerId !== pointerId) return;
      const dy = ev.pageY - startY;
      if (!started) {
        if (Math.abs(dy) < DRAG_THRESHOLD) return;
        started = true;
        document.body.style.userSelect = "none";
        document.body.style.cursor = "grabbing";
        window.getSelection()?.removeAllRanges();
      }
      // Its landing spot: past every other row whose middle it's crossed.
      const c = center + dy;
      to = boxes.reduce((n, b, i) => (i !== from && b.top + b.height / 2 < c ? n + 1 : n), 0);
      setDrag({ id, from, to, dy, shift });
    }

    function end(drop: boolean) {
      window.removeEventListener("pointermove", onMove);
      window.removeEventListener("pointerup", onUp);
      window.removeEventListener("pointercancel", onCancel);
      window.removeEventListener("keydown", onKey);
      document.body.style.userSelect = "";
      document.body.style.cursor = "";
      if (!started) return;
      // The click that ends a drag shouldn't also open the task.
      const swallow = (ev: MouseEvent) => {
        ev.stopPropagation();
        ev.preventDefault();
      };
      window.addEventListener("click", swallow, { capture: true, once: true });
      setTimeout(() => window.removeEventListener("click", swallow, { capture: true }), 0);
      if (drop && to !== from) {
        ids.splice(to, 0, ...ids.splice(from, 1));
        reorder(ids, id);
      } else {
        // Back to where it started, gliding rather than snapping.
        measureRows();
        setDrag(null);
      }
    }
    function onUp(ev: PointerEvent) {
      if (ev.pointerId === pointerId) end(true);
    }
    function onCancel(ev: PointerEvent) {
      if (ev.pointerId === pointerId) end(false);
    }
    function onKey(ev: KeyboardEvent) {
      if (ev.key === "Escape") end(false);
    }
    window.addEventListener("pointermove", onMove);
    window.addEventListener("pointerup", onUp);
    window.addEventListener("pointercancel", onCancel);
    window.addEventListener("keydown", onKey);
  }

  /** Saves whatever changed in the open task. An emptied title keeps the old one. */
  function commit(d: Draft) {
    const task = list.find((t) => t.id === d.id);
    if (!task) return;
    const title = taskTitleSchema.safeParse(d.title);
    const description = taskDescriptionSchema.safeParse(d.description);
    const patch: { title?: string; description?: string | null } = {};
    if (title.success && title.data !== task.title) patch.title = title.data;
    if (description.success && description.data !== (task.description ?? null)) patch.description = description.data;
    if (Object.keys(patch).length > 0) run({ type: "edit", id: task.id, patch }, () => editTaskAction(task.id, patch));
  }

  function openTask(task: TaskView) {
    if (task.id.startsWith("pending-")) return;
    if (draft && draft.id !== task.id) commit(draft);
    setDraft({ id: task.id, title: task.title, description: task.description ?? "" });
  }

  function closeTask() {
    if (draft) commit(draft);
    setDraft(null);
  }

  // A press anywhere outside the open task (and its menus) closes it.
  const closeRef = useRef(closeTask);
  useEffect(() => {
    closeRef.current = closeTask;
  });
  const openId = draft?.id ?? null;
  useEffect(() => {
    if (!openId) return;
    function onDown(e: PointerEvent) {
      const target = e.target as Element | null;
      if (target?.closest(`[data-task-editor="${openId}"], [role="menu"]`)) return;
      closeRef.current();
    }
    document.addEventListener("pointerdown", onDown, true);
    return () => document.removeEventListener("pointerdown", onDown, true);
  }, [openId]);

  return (
    <section aria-labelledby="tasks-heading" className="mt-12">
      <div className="mb-4">
        <h2 id="tasks-heading" className="text-lg font-semibold tracking-[-0.02em] text-foreground">
          Tasks
        </h2>
        <p className="text-sm text-muted">What you&apos;ve decided to do for this goal.</p>
      </div>

      <div className="rounded-2xl border border-card-border bg-card p-1.5">
        {open.length > 0 && (
          <ul ref={listRef} className="flex flex-col gap-0.5">
            {open.map((task, index) => (
              <TaskRow
                key={task.id}
                task={task}
                offset={dragOffset(drag, index, task.id)}
                dragging={drag?.id === task.id}
                // Rows slide aside only mid-drag; on drop they take their new places at once.
                sliding={drag !== null}
                reorderable={canReorder}
                onDragStart={(e) => startDrag(e, task.id)}
                onMove={(by) => moveBy(task.id, by)}
                clock={clock}
                draft={draft?.id === task.id ? draft : null}
                onDraft={setDraft}
                onOpen={() => openTask(task)}
                onClose={closeTask}
                onToggle={() => {
                  if (draft?.id === task.id) closeTask();
                  const doneAt = task.doneAt ? null : new Date().toISOString();
                  run({ type: "edit", id: task.id, patch: { doneAt } }, () => setTaskDoneAction(task.id, doneAt !== null));
                }}
                onEstimate={(minutes) =>
                  run({ type: "edit", id: task.id, patch: { minutes } }, () => editTaskAction(task.id, { minutes }))
                }
                today={today}
                onPlan={(plannedFor) =>
                  run({ type: "edit", id: task.id, patch: { plannedFor } }, () => editTaskAction(task.id, { plannedFor }))
                }
                onDue={(dueOn) => run({ type: "edit", id: task.id, patch: { dueOn } }, () => editTaskAction(task.id, { dueOn }))}
                onDelete={() => run({ type: "remove", id: task.id }, () => deleteTaskAction(task.id))}
              />
            ))}
          </ul>
        )}
        <p aria-live="polite" className="sr-only">
          {announcement}
        </p>

        {/* New task, at the end of the list. Enter adds it and keeps the cursor here for the next. */}
        <form
          onSubmit={(e) => {
            e.preventDefault();
            add();
          }}
          className="flex min-h-12 items-center gap-3 rounded-xl px-3"
        >
          <span className="flex h-[18px] w-[18px] shrink-0 items-center justify-center text-muted">
            <HugeiconsIcon icon={Add01Icon} size={16} />
          </span>
          <label htmlFor={inputId} className="sr-only">
            New task
          </label>
          <input
            id={inputId}
            value={newTitle}
            maxLength={MAX_TASK_TITLE}
            onChange={(e) => {
              setNewTitle(e.target.value);
              setError(null);
            }}
            onKeyDown={(e) => {
              if (e.key === "Escape") setNewTitle("");
            }}
            placeholder="Add a task"
            className="h-12 min-w-0 flex-1 bg-transparent text-[0.95rem] text-foreground outline-none placeholder:text-muted/80"
          />
          {newTitle.trim() && <span className="hidden shrink-0 text-xs text-muted sm:block">↵ to add</span>}
        </form>
      </div>

      {error && (
        <p role="alert" className="mt-2 text-sm text-red-600 dark:text-red-400">
          {error}
        </p>
      )}

      {hasRead && (
        <div aria-busy={reading} className="mt-6">
          <p className="mb-2 flex items-center gap-1.5 px-1 text-sm">
            <span className="font-medium text-foreground">Suggested</span>
            <span className="text-muted">from your latest read</span>
          </p>

          {shown.length > 0 ? (
            <ul className={`flex flex-col gap-2 transition-opacity ${reading ? "opacity-50" : ""}`}>
              {shown.map((s) => (
                <SuggestedRow
                  key={s.title}
                  suggestion={s}
                  disabled={reading}
                  onAdd={() => addSuggestion(s)}
                  onPass={() => passOn(s)}
                />
              ))}
            </ul>
          ) : (
            <div className="flex flex-wrap items-center justify-between gap-3 rounded-xl border border-dashed border-foreground/15 px-4 py-3">
              <p className="text-sm text-muted">{reading ? "Looking for what's next…" : "Nothing suggested right now."}</p>
              <button
                type="button"
                onClick={onRefresh}
                disabled={reading}
                className="flex h-8 items-center gap-1.5 rounded-lg border border-card-border bg-card px-3 text-sm font-medium text-foreground shadow-[0_1px_2px_rgb(15_17_20/0.05)] transition-colors hover:border-line-strong disabled:opacity-50"
              >
                <HugeiconsIcon icon={Refresh01Icon} size={14} className={reading ? "animate-spin" : undefined} />
                {reading ? "Reading…" : "Get new suggestions"}
              </button>
            </div>
          )}
        </div>
      )}
    </section>
  );
}

/** A suggestion: laid out like a task, but dashed and without a checkbox, since it isn't yours yet. */
function SuggestedRow({
  suggestion,
  disabled,
  onAdd,
  onPass,
}: {
  suggestion: SuggestionView;
  disabled: boolean;
  onAdd: () => void;
  onPass: () => void;
}) {
  return (
    // 18px sides: the Tasks card's border, padding and row padding add up to the same, so circles and text line up.
    <li className="flex items-start gap-3 rounded-xl border border-dashed border-foreground/15 px-[18px] py-1.5">
      <span className={`flex shrink-0 py-1.5 ${LINE}`}>
        {/* The icon's circle is drawn inside a margin, so it's sized up to match the 18px task checkbox. */}
        <span className="flex h-[1lh] w-[18px] items-center justify-center text-muted/70">
          <HugeiconsIcon icon={DashedLineCircleIcon} size={21} className="shrink-0" />
        </span>
      </span>
      <div className="min-w-0 flex-1 pb-2 pt-1.5">
        <p className={`text-foreground [overflow-wrap:anywhere] ${LINE}`}>{suggestion.title}</p>
        {suggestion.why && <p className={`line-clamp-2 ${DESCRIPTION}`}>{suggestion.why}</p>}
        <span className={`mt-1.5 ${PILL}`}>
          <HugeiconsIcon icon={Clock01Icon} size={12} />
          {minutesLabel(suggestion.minutes)}
        </span>
      </div>
      <span className={`flex shrink-0 gap-1 py-1.5 ${LINE}`}>
        <span className="flex h-[1lh] items-center gap-1">
          <button
            type="button"
            onClick={onAdd}
            disabled={disabled}
            aria-label={`Add “${suggestion.title}” as a task`}
            title="Add as task"
            className="flex h-7 items-center gap-1 rounded-lg border border-card-border bg-card px-2 text-xs font-medium text-foreground shadow-[0_1px_2px_rgb(15_17_20/0.05)] transition-colors hover:border-line-strong disabled:opacity-50"
          >
            <HugeiconsIcon icon={Add01Icon} size={13} />
            Add
          </button>
          <button
            type="button"
            onClick={onPass}
            disabled={disabled}
            aria-label={`Not now: “${suggestion.title}”`}
            title="Not now"
            className="flex h-7 w-7 items-center justify-center rounded-lg text-muted transition-colors hover:bg-wash hover:text-foreground disabled:opacity-50"
          >
            <HugeiconsIcon icon={Cancel01Icon} size={14} />
          </button>
        </span>
      </span>
    </li>
  );
}

/** "Today 14:00", "Tomorrow 9:30 AM" or "Thu 14:00", in the viewer's time zone. */
function scheduleLabel(iso: string, clock: Clock) {
  const at = new Date(iso);
  const midnight = (d: Date) => new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime();
  const days = Math.round((midnight(at) - midnight(new Date())) / 86_400_000);
  const day = days === 0 ? "Today" : days === 1 ? "Tomorrow" : at.toLocaleDateString(undefined, { weekday: "short" });
  return `${day} ${formatTime(at.getHours() * 60 + at.getMinutes(), clock)}`;
}

function TaskRow({
  task,
  offset,
  dragging,
  sliding,
  reorderable,
  onDragStart,
  onMove,
  clock,
  draft,
  onDraft,
  onOpen,
  onClose,
  onToggle,
  onEstimate,
  today,
  onPlan,
  onDue,
  onDelete,
}: {
  task: TaskView;
  /** How far it's moved while a task is dragged, in pixels. */
  offset: number;
  /** Whether it's the task being dragged. */
  dragging: boolean;
  /** Whether a drag is under way, so rows slide rather than jump. */
  sliding: boolean;
  /** Whether it can be dragged or moved from the keyboard right now. */
  reorderable: boolean;
  onDragStart: (e: React.PointerEvent<HTMLLIElement>) => void;
  onMove: (by: -1 | 1) => void;
  clock: Clock;
  /** Set while this task is open. */
  draft: Draft | null;
  onDraft: (draft: Draft) => void;
  onOpen: () => void;
  onClose: () => void;
  onToggle: () => void;
  onEstimate: (minutes: number) => void;
  today: string;
  onPlan: (day: string | null) => void;
  onDue: (day: string | null) => void;
  onDelete: () => void;
}) {
  const description = useRef<HTMLTextAreaElement>(null);
  const pending = task.id.startsWith("pending-");
  const isOpen = draft !== null;
  const firstLine = task.description?.split("\n").find((l) => l.trim()) ?? null;

  const checkbox = (
    <span className={`flex shrink-0 py-1.5 ${LINE}`}>
      <span className="flex h-[1lh] items-center">
        <button
          type="button"
          role="checkbox"
          aria-checked={task.doneAt !== null}
          aria-label={`Mark “${task.title}” as done`}
          disabled={pending}
          onClick={onToggle}
          className="flex h-[18px] w-[18px] items-center justify-center rounded-full border-[1.5px] border-foreground/30 text-transparent transition-colors hover:border-foreground/60 hover:text-foreground/40 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-foreground/30"
        >
          <HugeiconsIcon icon={Tick02Icon} size={12} strokeWidth={2.5} />
        </button>
      </span>
    </span>
  );

  const estimate = pending ? (
    <span className={PILL}>
      <HugeiconsIcon icon={Clock01Icon} size={12} />
      {minutesLabel(task.minutes)}
    </span>
  ) : (
    <DropdownMenu.Root>
      <DropdownMenu.Trigger
        aria-label={`Estimate: ${minutesLabel(task.minutes)}`}
        // The same time pill as on suggestions; click it to change the estimate.
        className={`${PILL} bg-card transition-colors hover:border-line-strong hover:text-foreground focus-visible:outline-2 focus-visible:outline-foreground/30 data-[state=open]:border-line-strong data-[state=open]:text-foreground`}
      >
        <HugeiconsIcon icon={Clock01Icon} size={12} />
        {minutesLabel(task.minutes)}
      </DropdownMenu.Trigger>
      <DropdownMenu.Portal>
        <DropdownMenu.Content
          align="end"
          sideOffset={6}
          collisionPadding={12}
          className="z-50 w-36 rounded-xl border border-card-border bg-card p-1 shadow-[0_12px_32px_-12px_rgb(0_0_0/0.25)] outline-none data-[state=open]:animate-[pop-in_120ms_ease-out]"
        >
          <DropdownMenu.Label className="px-2.5 pb-1 pt-1.5 text-xs font-medium text-muted">Estimate</DropdownMenu.Label>
          <DropdownMenu.RadioGroup value={String(task.minutes)} onValueChange={(v) => onEstimate(Number(v))}>
            {TASK_MINUTES.map((m) => (
              <DropdownMenu.RadioItem
                key={m}
                value={String(m)}
                className="flex h-8 cursor-default select-none items-center justify-between rounded-lg px-2.5 text-sm text-foreground outline-none data-[highlighted]:bg-wash"
              >
                {minutesLabel(m)}
                <DropdownMenu.ItemIndicator>
                  <HugeiconsIcon icon={Tick02Icon} size={14} className="text-muted" />
                </DropdownMenu.ItemIndicator>
              </DropdownMenu.RadioItem>
            ))}
          </DropdownMenu.RadioGroup>
        </DropdownMenu.Content>
      </DropdownMenu.Portal>
    </DropdownMenu.Root>
  );

  // An empty pill waits for hover or focus on a closed row; on touch screens, for the open task.
  // While any menu on the row is open (the pointer is off in the menu), the row stays as it was on hover.
  const quiet = isOpen
    ? ""
    : "opacity-0 group-hover:opacity-100 group-has-[[data-state=open]]:opacity-100 focus-visible:opacity-100 data-[state=open]:opacity-100 [@media(hover:none)]:hidden";
  // A time on the calendar says when already; the planned day follows it.
  const plan = !task.scheduledAt && (
    <DayPill
      key="plan"
      kind="plan"
      value={task.plannedFor}
      today={today}
      onChange={onPlan}
      disabled={pending}
      className={task.plannedFor ? "" : quiet}
    />
  );
  const due = (
    <DayPill
      key="due"
      kind="due"
      value={task.dueOn}
      today={today}
      onChange={onDue}
      disabled={pending}
      className={task.dueOn ? "" : quiet}
    />
  );
  // Set pills first and empty ones after, so a hidden empty pill never leaves a gap between the others.
  const days = !task.plannedFor && task.dueOn ? [due, plan] : [plan, due];

  if (isOpen) {
    return (
      <li
        data-task-editor={task.id}
        onKeyDown={(e) => {
          // Esc inside the estimate menu just closes the menu.
          if ((e.target as HTMLElement).closest("[role='menu']")) return;
          if (e.key === "Escape" || (e.key === "Enter" && (e.metaKey || e.ctrlKey))) {
            e.preventDefault();
            onClose();
          }
        }}
        className="flex items-start gap-3 rounded-xl bg-wash/70 px-3 pb-3 pt-1.5"
      >
        {checkbox}
        <div className="min-w-0 flex-1">
          <input
            aria-label="Task"
            value={draft.title}
            maxLength={MAX_TASK_TITLE}
            onChange={(e) => onDraft({ ...draft, title: e.target.value })}
            onKeyDown={(e) => {
              if (e.key === "Enter" && !e.metaKey && !e.ctrlKey) {
                e.preventDefault();
                description.current?.focus();
              }
            }}
            // Same weight as the closed row, so opening doesn't make the title jump.
            className={`block w-full bg-transparent pt-1.5 text-foreground outline-none ${LINE}`}
          />
          <textarea
            ref={description}
            autoFocus
            aria-label="Description"
            value={draft.description}
            maxLength={MAX_TASK_DESCRIPTION}
            rows={1}
            // Start with the cursor at the end, ready to keep writing.
            onFocus={(e) => e.currentTarget.setSelectionRange(e.currentTarget.value.length, e.currentTarget.value.length)}
            onChange={(e) => onDraft({ ...draft, description: e.target.value })}
            placeholder="Add a description…"
            // Same type as the description on the closed row; only the clamping differs.
            className={`block w-full resize-none bg-transparent outline-none [field-sizing:content] placeholder:text-muted/70 ${DESCRIPTION}`}
          />
          <div className="mt-1.5 flex flex-wrap items-center gap-x-2 gap-y-1">
            {estimate}
            {days}
          </div>
        </div>
      </li>
    );
  }

  return (
    <li
      data-task-row={task.id}
      onPointerDown={onDragStart}
      style={offset ? { transform: `translateY(${offset}px)` } : undefined}
      className={`group relative flex min-h-12 items-start gap-3 rounded-xl px-3 py-1.5 ${
        dragging
          ? "z-10 bg-card shadow-[0_10px_28px_-10px_rgb(0_0_0/0.35)] ring-1 ring-card-border"
          : `hover:bg-wash/50 ${sliding ? "transition-[transform,background-color] duration-150 ease-out" : "transition-colors"}`
      } ${pending ? "opacity-60" : ""}`}
    >
      {/* A grip in the left margin: a hint on hover, and the only place a drag starts on touch screens. */}
      {reorderable && (
        <span
          data-task-grip
          aria-hidden="true"
          className={`absolute -left-1.5 top-1.5 flex w-[18px] cursor-grab touch-none justify-center py-1.5 text-muted ${LINE}`}
        >
          <span
            className={`flex h-[1lh] items-center transition-opacity ${
              dragging ? "opacity-60" : "opacity-0 group-hover:opacity-50 [@media(hover:none)]:opacity-50"
            }`}
          >
            <HugeiconsIcon icon={DragDropVerticalIcon} size={12} />
          </span>
        </span>
      )}
      {checkbox}
      <div className="min-w-0 flex-1 pb-2">
        <button
          type="button"
          data-task-open
          onClick={onOpen}
          onKeyDown={(e) => {
            if (!e.altKey || (e.key !== "ArrowUp" && e.key !== "ArrowDown")) return;
            e.preventDefault();
            onMove(e.key === "ArrowUp" ? -1 : 1);
          }}
          disabled={pending}
          aria-label={`Open “${task.title}”`}
          aria-keyshortcuts={reorderable ? "Alt+ArrowUp Alt+ArrowDown" : undefined}
          className="block w-full cursor-pointer pt-1.5 text-left outline-none focus-visible:underline"
        >
          <span className={`block text-foreground [overflow-wrap:anywhere] ${LINE}`}>{task.title}</span>
          {/* Clamped rather than truncated, so the ellipsis follows the last whole word. */}
          {firstLine && <span className={`line-clamp-1 ${DESCRIPTION}`}>{firstLine}</span>}
        </button>
        <div className="mt-1.5 flex flex-wrap items-center gap-x-2.5 gap-y-1">
          {estimate}
          {task.scheduledAt && (
            <span className="flex items-center gap-1 text-xs text-muted" suppressHydrationWarning>
              <HugeiconsIcon icon={Calendar03Icon} size={12} />
              {scheduleLabel(task.scheduledAt, clock)}
            </span>
          )}
          {days}
        </div>
      </div>
      {/* Floats over the content's top-right corner on hover, so the text keeps the full width. */}
      {!pending && (
        <span className={`absolute right-2 top-1.5 flex py-1.5 ${LINE}`}>
          <span className="flex h-[1lh] items-center opacity-0 transition-opacity focus-within:opacity-100 group-hover:opacity-100 has-[[data-state=open]]:opacity-100 [@media(hover:none)]:opacity-100">
            <MoreMenu label={`Options for ${task.title}`} small>
              <MoreMenuItem icon={ViewIcon} onSelect={onOpen}>
                Open
              </MoreMenuItem>
              <MoreMenuItem icon={Delete02Icon} destructive onSelect={onDelete}>
                Delete
              </MoreMenuItem>
            </MoreMenu>
          </span>
        </span>
      )}
    </li>
  );
}
