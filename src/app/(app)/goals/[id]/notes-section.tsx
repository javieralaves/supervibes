"use client";

import { ArrowTurnBackwardIcon, Calendar03Icon, Delete02Icon, PencilEdit02Icon, Tick02Icon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import { startTransition, useId, useOptimistic, useState, useTransition } from "react";

import { Avatar } from "@/components/avatar";
import { Breadcrumbs } from "@/components/breadcrumbs";
import { ConfirmDialog } from "@/components/confirm-dialog";
import { MoreMenu, MoreMenuItem } from "@/components/more-menu";
import { formatRange, useClock } from "@/lib/clock";
import { MAX_POST, postBodySchema } from "@/lib/post-schema";
import type { Breadcrumb, RecapSession } from "@/lib/recap-schema";
import type { Clock } from "@/lib/settings-schema";
import { shortAgo } from "@/lib/time";

import { addPostAction, deletePostAction, editPostAction, setTaskDoneAction } from "./actions";

export type NoteView = {
  id: string;
  body: string;
  /** Title of the suggestion this note marks as done, if it came from "Done" on a suggestion. */
  completedSuggestion?: string | null;
  /** Title of the task this records as done, if it was posted by checking a task off. */
  completedTask?: string | null;
  /** The task it records, while that task still exists, so it can be reopened from here. */
  taskId?: string | null;
  /** That task's description, if it has one. */
  taskDescription?: string | null;
  /** The calendar session this recaps, if it's a recap. */
  session?: RecapSession | null;
  /** Links to specific things in connected apps the recap drew on. */
  breadcrumbs?: Breadcrumb[] | null;
  createdAt: string;
  updatedAt: string;
};
export type NoteAuthor = { name: string; image: string | null | undefined };

type Op = { type: "add"; note: NoteView } | { type: "edit"; id: string; body: string } | { type: "delete"; id: string };

function applyOp(notes: NoteView[], op: Op): NoteView[] {
  switch (op.type) {
    case "add":
      return [op.note, ...notes];
    case "edit":
      return notes.map((n) => (n.id === op.id ? { ...n, body: op.body, updatedAt: new Date().toISOString() } : n));
    case "delete":
      return notes.filter((n) => n.id !== op.id);
  }
}

const textareaClass =
  "block w-full resize-none bg-transparent text-[0.95rem] leading-relaxed text-foreground outline-none [field-sizing:content] placeholder:text-muted/80";

/** Per-goal notes: context the person adds that no connected app can show. */
export function NotesSection({
  goalId,
  notes,
  author,
  clock,
}: {
  goalId: string;
  notes: NoteView[];
  author: NoteAuthor;
  /** The user's clock choice, for recapped sessions' times. */
  clock: Clock | null;
}) {
  const [optimisticNotes, apply] = useOptimistic(notes, applyOp);
  const [draft, setDraft] = useState("");
  const [posting, startPosting] = useTransition();
  const [error, setError] = useState<string | null>(null);
  const fieldId = useId();

  function post() {
    const parsed = postBodySchema.safeParse(draft);
    if (!parsed.success) {
      setError(parsed.error.issues[0]?.message ?? "Check the note.");
      return;
    }
    setError(null);
    const body = parsed.data;
    const now = new Date().toISOString();
    setDraft("");
    startPosting(async () => {
      apply({ type: "add", note: { id: `pending-${now}`, body, createdAt: now, updatedAt: now } });
      const result = await addPostAction(goalId, body);
      if (!result.ok) {
        setDraft(body);
        setError(result.error);
      }
    });
  }

  function run(op: Op, action: () => Promise<{ ok: boolean; error?: string }>) {
    setError(null);
    startTransition(async () => {
      apply(op);
      const result = await action();
      if (!result.ok) setError(result.error ?? "That didn't save.");
    });
  }

  return (
    <section aria-labelledby="activity-heading" className="mt-12">
      <div className="mb-4">
        <h2 id="activity-heading" className="text-lg font-semibold tracking-[-0.02em] text-foreground">
          Activity
        </h2>
        <p className="text-sm text-muted">Your notes and finished tasks. All of it feeds the progress read.</p>
      </div>

      {/* Composer */}
      <form
        onSubmit={(e) => {
          e.preventDefault();
          post();
        }}
        className="rounded-2xl border border-card-border bg-card px-4 py-3.5 sm:px-5"
      >
        <label htmlFor={fieldId} className="sr-only">
          New note
        </label>
        <textarea
          id={fieldId}
          rows={2}
          value={draft}
          maxLength={MAX_POST}
          onChange={(e) => {
            setDraft(e.target.value);
            setError(null);
          }}
          onKeyDown={(e) => {
            if (e.key === "Enter" && (e.metaKey || e.ctrlKey)) {
              e.preventDefault();
              post();
            }
          }}
          placeholder="Add context, like a decision, offline work, or something to ignore…"
          className={`${textareaClass} min-h-[3.25rem]`}
        />
        <div className="mt-2 flex items-center justify-between gap-3">
          <p className={`text-xs ${error ? "text-red-600 dark:text-red-400" : "text-muted"}`} role={error ? "alert" : undefined}>
            {error ?? (draft.trim() ? "⌘↵ to post" : "")}
          </p>
          <button
            type="submit"
            disabled={posting || !draft.trim()}
            className="h-8 shrink-0 rounded-lg bg-foreground px-3 text-sm font-semibold text-background transition-opacity hover:opacity-90 disabled:opacity-30"
          >
            Post
          </button>
        </div>
      </form>

      {optimisticNotes.length > 0 && (
        <ul className="mt-3 grid gap-3">
          {optimisticNotes.map((note) =>
            note.completedTask ? (
              <TaskDoneCard
                key={note.id}
                note={note}
                task={note.completedTask}
                author={author}
                // Reopening the task also takes this entry back out of the activity.
                onReopen={
                  note.taskId
                    ? () => run({ type: "delete", id: note.id }, () => setTaskDoneAction(note.taskId, false))
                    : undefined
                }
                onDelete={() => run({ type: "delete", id: note.id }, () => deletePostAction(note.id))}
              />
            ) : (
              <NoteCard
                key={note.id}
                note={note}
                author={author}
                clock={clock}
                onEdit={(body) => run({ type: "edit", id: note.id, body }, () => editPostAction(note.id, body))}
                onDelete={() => run({ type: "delete", id: note.id }, () => deletePostAction(note.id))}
              />
            ),
          )}
        </ul>
      )}
    </section>
  );
}

/** Posted automatically when a task is checked off: who, when, and the task itself. */
function TaskDoneCard({
  note,
  task,
  author,
  onReopen,
  onDelete,
}: {
  note: NoteView;
  task: string;
  author: NoteAuthor;
  /** Missing when the task has since been deleted. */
  onReopen?: () => void;
  onDelete: () => void;
}) {
  const [confirming, setConfirming] = useState(false);

  return (
    <li className="rounded-2xl border border-card-border bg-card px-4 py-4 sm:px-5">
      <div className="flex items-center gap-3">
        <Avatar name={author.name} image={author.image} size="sm" />
        <div className="min-w-0 flex-1">
          <p className="truncate text-sm font-semibold text-foreground">{author.name}</p>
          <p className="text-xs text-muted" suppressHydrationWarning>
            Completed a task · {shortAgo(note.createdAt)}
          </p>
        </div>
        <MoreMenu label="Options for this entry">
          {onReopen && (
            <MoreMenuItem icon={ArrowTurnBackwardIcon} onSelect={onReopen}>
              Reopen task
            </MoreMenuItem>
          )}
          <MoreMenuItem icon={Delete02Icon} destructive onSelect={() => setConfirming(true)}>
            Delete
          </MoreMenuItem>
        </MoreMenu>
      </div>

      <CompletedTitle kind="task">{task}</CompletedTitle>
      {note.taskDescription && <p className={`mt-1 line-clamp-3 ${detailClass}`}>{note.taskDescription}</p>}

      <ConfirmDialog
        open={confirming}
        onOpenChange={setConfirming}
        title="Delete this entry?"
        description="The task stays done. Only this entry is removed from your activity."
        confirmLabel="Delete"
        pendingLabel="Deleting…"
        pending={false}
        onConfirm={() => {
          setConfirming(false);
          onDelete();
        }}
      />
    </li>
  );
}

/** What a completion entry's text under the title looks like. */
const detailClass = "whitespace-pre-wrap text-sm leading-relaxed text-muted [overflow-wrap:anywhere]";

/** A finished task or suggestion: a small check inline with its title, so text below lines up under both. */
function CompletedTitle({ kind, children }: { kind: "task" | "suggestion"; children: React.ReactNode }) {
  return (
    <p className="mt-3 text-[0.95rem] font-medium leading-relaxed text-foreground [overflow-wrap:anywhere]">
      <span
        aria-hidden="true"
        className="mr-2 inline-flex h-3.5 w-3.5 -translate-y-px items-center justify-center rounded-full bg-foreground align-middle text-background"
      >
        <HugeiconsIcon icon={Tick02Icon} size={9} strokeWidth={3} />
      </span>
      <span className="sr-only">Completed {kind}: </span>
      {children}
    </p>
  );
}

function NoteCard({
  note,
  author,
  clock,
  onEdit,
  onDelete,
}: {
  note: NoteView;
  author: NoteAuthor;
  clock: Clock | null;
  onEdit: (body: string) => void;
  onDelete: () => void;
}) {
  const [editing, setEditing] = useState(false);
  const [draft, setDraft] = useState(note.body);
  const [confirming, setConfirming] = useState(false);
  const pending = note.id.startsWith("pending-");
  const edited = new Date(note.updatedAt).getTime() - new Date(note.createdAt).getTime() > 1000;
  // Posted from "Done" on a suggestion: shown like a completed task, with the note as its detail.
  const completion = Boolean(note.completedSuggestion);
  // Posted from "Recap session" on a calendar block.
  const session = note.session ?? null;

  function save() {
    const parsed = postBodySchema.safeParse(draft);
    if (!parsed.success) return;
    setEditing(false);
    if (parsed.data !== note.body) onEdit(parsed.data);
  }

  function cancel() {
    setDraft(note.body);
    setEditing(false);
  }

  return (
    <li
      className={`rounded-2xl border bg-card px-4 py-4 transition-[border-color,box-shadow] sm:px-5 ${
        editing
          ? "border-line-strong shadow-[0_0_0_4px_color-mix(in_oklab,var(--foreground)_6%,transparent)]"
          : "border-card-border"
      } ${pending ? "opacity-60" : ""}`}
    >
      {/* Who and when, with the note's menu on the same row. */}
      <div className="flex items-center gap-3">
        <Avatar name={author.name} image={author.image} size="sm" />
        <div className="min-w-0 flex-1">
          <p className="truncate text-sm font-semibold text-foreground">{author.name}</p>
          <p className="text-xs text-muted" suppressHydrationWarning>
            {completion && !pending ? "Completed a suggestion · " : ""}
            {session && !pending ? "Recapped a session · " : ""}
            {pending ? "Posting…" : shortAgo(note.createdAt)}
            {edited && !pending ? " · edited" : ""}
          </p>
        </div>
        {!editing && !pending && (
          <MoreMenu label="Note options">
            <MoreMenuItem
              icon={PencilEdit02Icon}
              onSelect={() => {
                setDraft(note.body);
                setEditing(true);
              }}
            >
              Edit
            </MoreMenuItem>
            <MoreMenuItem icon={Delete02Icon} destructive onSelect={() => setConfirming(true)}>
              Delete
            </MoreMenuItem>
          </MoreMenu>
        )}
      </div>

      {completion && <CompletedTitle kind="suggestion">{note.completedSuggestion}</CompletedTitle>}
      {session && <SessionLine session={session} clock={clock} />}

      {editing ? (
        <div className={completion ? "mt-1" : session ? "mt-2" : "mt-3"}>
          <label className="sr-only" htmlFor={`edit-${note.id}`}>
            Edit note
          </label>
          <textarea
            id={`edit-${note.id}`}
            autoFocus
            value={draft}
            maxLength={MAX_POST}
            // Start editing with the cursor at the end, not before the existing text.
            onFocus={(e) => {
              const end = e.currentTarget.value.length;
              e.currentTarget.setSelectionRange(end, end);
            }}
            onChange={(e) => setDraft(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === "Enter" && (e.metaKey || e.ctrlKey)) {
                e.preventDefault();
                save();
              }
              if (e.key === "Escape") cancel();
            }}
            // Same type and position as the note itself, so editing happens in place.
            className={
              completion
                ? "block w-full resize-none bg-transparent text-sm leading-relaxed text-foreground outline-none [field-sizing:content] [overflow-wrap:anywhere]"
                : `${textareaClass} [overflow-wrap:anywhere]`
            }
          />
          <div className="mt-3 flex items-center justify-between gap-3">
            <p className="hidden text-xs text-muted sm:block">⌘↵ to save · Esc to cancel</p>
            <div className="ml-auto flex gap-1.5">
            <button type="button" onClick={cancel} className="h-8 rounded-lg px-3 text-sm font-medium text-muted hover:bg-wash hover:text-foreground">
              Cancel
            </button>
            <button
              type="button"
              onClick={save}
              disabled={!draft.trim()}
              className="h-8 rounded-lg bg-foreground px-3 text-sm font-semibold text-background hover:opacity-90 disabled:opacity-30"
            >
              Save
            </button>
            </div>
          </div>
        </div>
      ) : (
        <>
          <p
            className={
              completion
                ? `mt-1 ${detailClass}`
                : `${session ? "mt-2" : "mt-3"} whitespace-pre-wrap text-[0.95rem] leading-relaxed text-foreground [overflow-wrap:anywhere]`
            }
          >
            {note.body}
          </p>
          {note.breadcrumbs && <Breadcrumbs items={note.breadcrumbs} className="mt-2.5" />}
        </>
      )}

      <ConfirmDialog
        open={confirming}
        onOpenChange={setConfirming}
        title="Delete this note?"
        description="Future progress reads won't take it into account."
        confirmLabel="Delete"
        pendingLabel="Deleting…"
        pending={false}
        onConfirm={() => {
          setConfirming(false);
          onDelete();
        }}
      />
    </li>
  );
}

/** Which calendar session a recap covers, in the viewer's time zone: "Tue, Nov 17 · 10:00–11:20 PM · Title". */
function SessionLine({ session, clock }: { session: RecapSession; clock: Clock | null }) {
  const resolved = useClock(clock);
  const start = new Date(session.startsAt);
  const end = new Date(session.endsAt);
  const minutes = (d: Date) => d.getHours() * 60 + d.getMinutes();
  const day = start.toLocaleDateString("en-US", { weekday: "short", month: "short", day: "numeric" });
  return (
    <p className="mt-3 flex items-center gap-1.5 text-[13px] text-muted">
      <HugeiconsIcon icon={Calendar03Icon} size={14} className="shrink-0" />
      {/* Times are the viewer's local ones, which the server can't know. */}
      <span className="shrink-0 tabular-nums" suppressHydrationWarning>
        {day} · {formatRange(minutes(start), minutes(end), resolved)}
      </span>
      <span aria-hidden="true">·</span>
      <span className="min-w-0 truncate font-medium text-foreground/75">{session.title}</span>
    </p>
  );
}
