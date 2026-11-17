"use client";

import {
  Add01Icon,
  Cancel01Icon,
  Clock01Icon,
  DashedLineCircleIcon,
  Delete02Icon,
  Refresh01Icon,
  SparklesIcon,
  Tick02Icon,
  ViewIcon,
} from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import * as DropdownMenu from "@radix-ui/react-dropdown-menu";
import { startTransition, useEffect, useId, useOptimistic, useRef, useState } from "react";

import { MoreMenu, MoreMenuItem } from "@/components/more-menu";
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
  setTaskDoneAction,
  type ActionResult,
} from "./actions";

export type TaskView = { id: string; title: string; description: string | null; minutes: number; doneAt: string | null };
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
 * it saves when it closes (click elsewhere, Esc, or open another). Checked-off
 * tasks move to the goal's Activity.
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
}) {
  const [list, apply] = useOptimistic(tasks, applyOp);
  const [shown, hide] = useOptimistic(suggestions, (all: SuggestionView[], title: string) =>
    all.filter((s) => s.title !== title),
  );
  const [newTitle, setNewTitle] = useState("");
  const [draft, setDraft] = useState<Draft | null>(null);
  const [error, setError] = useState<string | null>(null);
  const inputId = useId();

  const open = list.filter((t) => !t.doneAt);
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
        task: { id: `pending-${++pendingSeq}`, title: s.title, description: s.why || null, minutes: s.minutes, doneAt: null },
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
        task: { id: `pending-${++pendingSeq}`, title: parsed.data, description: null, minutes: DEFAULT_TASK_MINUTES, doneAt: null },
      },
      () => addTaskAction(goalId, parsed.data),
    );
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
          <ul className="flex flex-col gap-0.5">
            {open.map((task) => (
              <TaskRow
                key={task.id}
                task={task}
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
                onDelete={() => run({ type: "remove", id: task.id }, () => deleteTaskAction(task.id))}
              />
            ))}
          </ul>
        )}

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
            <HugeiconsIcon icon={SparklesIcon} size={14} className="text-muted" />
            <span className="font-medium text-foreground">Suggested</span>
            <span className="text-muted">· from your latest read</span>
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

function TaskRow({
  task,
  draft,
  onDraft,
  onOpen,
  onClose,
  onToggle,
  onEstimate,
  onDelete,
}: {
  task: TaskView;
  /** Set while this task is open. */
  draft: Draft | null;
  onDraft: (draft: Draft) => void;
  onOpen: () => void;
  onClose: () => void;
  onToggle: () => void;
  onEstimate: (minutes: number) => void;
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
          <div className="mt-1.5">{estimate}</div>
        </div>
      </li>
    );
  }

  return (
    <li className={`group relative flex min-h-12 items-start gap-3 rounded-xl px-3 py-1.5 transition-colors hover:bg-wash/50 ${pending ? "opacity-60" : ""}`}>
      {checkbox}
      <div className="min-w-0 flex-1 pb-2">
        <button
          type="button"
          onClick={onOpen}
          disabled={pending}
          aria-label={`Open “${task.title}”`}
          className="block w-full cursor-pointer pt-1.5 text-left outline-none focus-visible:underline"
        >
          <span className={`block text-foreground [overflow-wrap:anywhere] ${LINE}`}>{task.title}</span>
          {/* Clamped rather than truncated, so the ellipsis follows the last whole word. */}
          {firstLine && <span className={`line-clamp-1 ${DESCRIPTION}`}>{firstLine}</span>}
        </button>
        <div className="mt-1.5">{estimate}</div>
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
