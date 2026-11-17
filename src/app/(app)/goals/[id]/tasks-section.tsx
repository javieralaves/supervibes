"use client";

import { Add01Icon, ArrowDown01Icon, Delete02Icon, PencilEdit02Icon, Tick02Icon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import * as DropdownMenu from "@radix-ui/react-dropdown-menu";
import { startTransition, useId, useOptimistic, useRef, useState } from "react";

import { MoreMenu, MoreMenuItem } from "@/components/more-menu";
import { DEFAULT_TASK_MINUTES, MAX_TASK_TITLE, minutesLabel, TASK_MINUTES, taskTitleSchema } from "@/lib/task-schema";

import { addTaskAction, deleteTaskAction, editTaskAction, setTaskDoneAction, type ActionResult } from "./actions";

export type TaskView = { id: string; title: string; minutes: number; doneAt: string | null };

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

let pendingSeq = 0;

/** A goal's tasks: things you've decided to do, open until checked off. */
export function TasksSection({ goalId, tasks }: { goalId: string; tasks: TaskView[] }) {
  const [list, apply] = useOptimistic(tasks, applyOp);
  const [draft, setDraft] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [showDone, setShowDone] = useState(false);
  const inputId = useId();

  const open = list.filter((t) => !t.doneAt);
  const done = list
    .filter((t) => t.doneAt)
    .sort((a, b) => Date.parse(b.doneAt!) - Date.parse(a.doneAt!));

  function run(op: Op, action: () => Promise<ActionResult>) {
    setError(null);
    startTransition(async () => {
      apply(op);
      const result = await action();
      if (!result.ok) setError(result.error);
    });
  }

  function add() {
    const parsed = taskTitleSchema.safeParse(draft);
    if (!parsed.success) return;
    setDraft("");
    run(
      { type: "add", task: { id: `pending-${++pendingSeq}`, title: parsed.data, minutes: DEFAULT_TASK_MINUTES, doneAt: null } },
      () => addTaskAction(goalId, parsed.data),
    );
  }

  const rowProps = (task: TaskView) => ({
    task,
    onToggle: () => {
      const doneAt = task.doneAt ? null : new Date().toISOString();
      run({ type: "edit", id: task.id, patch: { doneAt } }, () => setTaskDoneAction(task.id, doneAt !== null));
    },
    onRename: (title: string) => run({ type: "edit", id: task.id, patch: { title } }, () => editTaskAction(task.id, { title })),
    onEstimate: (minutes: number) =>
      run({ type: "edit", id: task.id, patch: { minutes } }, () => editTaskAction(task.id, { minutes })),
    onDelete: () => run({ type: "remove", id: task.id }, () => deleteTaskAction(task.id)),
  });

  return (
    <section aria-labelledby="tasks-heading" className="mt-12">
      <div className="mb-4">
        <h2 id="tasks-heading" className="text-lg font-semibold tracking-[-0.02em] text-foreground">
          Tasks
        </h2>
        <p className="text-sm text-muted">What you&apos;ve decided to do for this goal.</p>
      </div>

      <div className="overflow-hidden rounded-2xl border border-card-border bg-card">
        {open.length > 0 && (
          <ul className="divide-y divide-card-border">
            {open.map((task) => (
              <TaskRow key={task.id} {...rowProps(task)} />
            ))}
          </ul>
        )}

        {/* New task, at the end of the list. Enter adds it and keeps the cursor here for the next. */}
        <form
          onSubmit={(e) => {
            e.preventDefault();
            add();
          }}
          className={`flex min-h-12 items-center gap-3 px-4 ${open.length > 0 ? "border-t border-card-border" : ""}`}
        >
          <span className="flex h-[18px] w-[18px] shrink-0 items-center justify-center text-muted">
            <HugeiconsIcon icon={Add01Icon} size={16} />
          </span>
          <label htmlFor={inputId} className="sr-only">
            New task
          </label>
          <input
            id={inputId}
            value={draft}
            maxLength={MAX_TASK_TITLE}
            onChange={(e) => {
              setDraft(e.target.value);
              setError(null);
            }}
            onKeyDown={(e) => {
              if (e.key === "Escape") setDraft("");
            }}
            placeholder="Add a task"
            className="h-12 min-w-0 flex-1 bg-transparent text-[0.95rem] text-foreground outline-none placeholder:text-muted/80"
          />
          {draft.trim() && <span className="hidden shrink-0 text-xs text-muted sm:block">↵ to add</span>}
        </form>
      </div>

      {error && (
        <p role="alert" className="mt-2 text-sm text-red-600 dark:text-red-400">
          {error}
        </p>
      )}

      {done.length > 0 && (
        <div className="mt-3">
          <button
            type="button"
            aria-expanded={showDone}
            onClick={() => setShowDone((v) => !v)}
            className="flex h-8 items-center gap-1.5 rounded-lg px-2 text-sm font-medium text-muted transition-colors hover:bg-wash hover:text-foreground"
          >
            Done · {done.length}
            <HugeiconsIcon
              icon={ArrowDown01Icon}
              size={14}
              className={`transition-transform ${showDone ? "rotate-180" : ""}`}
            />
          </button>
          {showDone && (
            <ul className="mt-2 divide-y divide-card-border overflow-hidden rounded-2xl border border-card-border bg-card">
              {done.map((task) => (
                <TaskRow key={task.id} {...rowProps(task)} />
              ))}
            </ul>
          )}
        </div>
      )}
    </section>
  );
}

function TaskRow({
  task,
  onToggle,
  onRename,
  onEstimate,
  onDelete,
}: {
  task: TaskView;
  onToggle: () => void;
  onRename: (title: string) => void;
  onEstimate: (minutes: number) => void;
  onDelete: () => void;
}) {
  const [editing, setEditing] = useState(false);
  const [draft, setDraft] = useState(task.title);
  const cancelled = useRef(false);
  const pending = task.id.startsWith("pending-");
  const isDone = task.doneAt !== null;

  function startEditing() {
    if (pending) return;
    cancelled.current = false;
    setDraft(task.title);
    setEditing(true);
  }

  function finish() {
    setEditing(false);
    if (cancelled.current) return;
    const parsed = taskTitleSchema.safeParse(draft);
    if (parsed.success && parsed.data !== task.title) onRename(parsed.data);
  }

  return (
    <li className={`group flex min-h-12 items-center gap-3 px-4 py-1.5 ${pending ? "opacity-60" : ""}`}>
      <button
        type="button"
        role="checkbox"
        aria-checked={isDone}
        aria-label={isDone ? `Mark “${task.title}” as open` : `Mark “${task.title}” as done`}
        disabled={pending}
        onClick={onToggle}
        className={`flex h-[18px] w-[18px] shrink-0 items-center justify-center rounded-full border-[1.5px] transition-colors focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-foreground/30 ${
          isDone
            ? "border-foreground bg-foreground text-background"
            : "border-foreground/30 text-transparent hover:border-foreground/60 hover:text-foreground/40"
        }`}
      >
        <HugeiconsIcon icon={Tick02Icon} size={12} strokeWidth={2.5} />
      </button>

      {editing ? (
        <input
          autoFocus
          aria-label="Task"
          value={draft}
          maxLength={MAX_TASK_TITLE}
          onChange={(e) => setDraft(e.target.value)}
          onFocus={(e) => e.currentTarget.setSelectionRange(e.currentTarget.value.length, e.currentTarget.value.length)}
          onBlur={finish}
          onKeyDown={(e) => {
            if (e.key === "Enter") e.currentTarget.blur();
            if (e.key === "Escape") {
              cancelled.current = true;
              e.currentTarget.blur();
            }
          }}
          className="min-w-0 flex-1 bg-transparent py-1.5 text-[0.95rem] text-foreground outline-none"
        />
      ) : (
        <p
          onClick={startEditing}
          className={`min-w-0 flex-1 cursor-text py-1.5 text-[0.95rem] leading-snug [overflow-wrap:anywhere] ${
            isDone ? "text-muted line-through decoration-foreground/25" : "text-foreground"
          }`}
        >
          {task.title}
        </p>
      )}

      {isDone || pending ? (
        <span className="shrink-0 text-xs tabular-nums text-muted">{minutesLabel(task.minutes)}</span>
      ) : (
        <DropdownMenu.Root>
          <DropdownMenu.Trigger
            aria-label={`Estimate: ${minutesLabel(task.minutes)}`}
            className="h-6 shrink-0 rounded-md px-1.5 text-xs font-medium tabular-nums text-muted transition-colors hover:bg-wash hover:text-foreground focus-visible:outline-2 focus-visible:outline-foreground/30 data-[state=open]:bg-wash data-[state=open]:text-foreground"
          >
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
      )}

      {/* Hidden while editing, so closing the menu can't pull focus back out of the field. */}
      {!pending && !editing && (
        <div className="shrink-0 opacity-0 transition-opacity focus-within:opacity-100 group-hover:opacity-100 has-[[data-state=open]]:opacity-100 [@media(hover:none)]:opacity-100">
          <MoreMenu label={`Options for ${task.title}`} small>
            <MoreMenuItem icon={PencilEdit02Icon} onSelect={startEditing}>
              Edit
            </MoreMenuItem>
            <MoreMenuItem icon={Delete02Icon} destructive onSelect={onDelete}>
              Delete
            </MoreMenuItem>
          </MoreMenu>
        </div>
      )}
    </li>
  );
}
