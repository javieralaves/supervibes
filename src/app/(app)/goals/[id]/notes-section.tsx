"use client";

import { ArrowTurnBackwardIcon, CheckmarkCircle02Icon, Delete02Icon, PencilEdit02Icon, Tick02Icon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import { startTransition, useId, useOptimistic, useState, useTransition } from "react";

import { Avatar } from "@/components/avatar";
import { ConfirmDialog } from "@/components/confirm-dialog";
import { MoreMenu, MoreMenuItem } from "@/components/more-menu";
import { MAX_POST, postBodySchema } from "@/lib/post-schema";
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
  onPosted,
}: {
  goalId: string;
  notes: NoteView[];
  author: NoteAuthor;
  /** Called after a new note is saved, to refresh the progress read. */
  onPosted: () => void;
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
      if (result.ok) {
        onPosted();
      } else {
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

      {/* The task, shown the way it looks when checked off in the Tasks list. */}
      <div className="mt-3 flex items-start gap-2.5 text-[0.95rem] leading-relaxed">
        {/* One line tall, so the check centres on the first line of the title. */}
        <span aria-hidden="true" className="flex h-[1lh] shrink-0 items-center">
          <span className="flex h-[18px] w-[18px] items-center justify-center rounded-full bg-foreground text-background">
            <HugeiconsIcon icon={Tick02Icon} size={12} strokeWidth={2.5} />
          </span>
        </span>
        <p className="min-w-0 font-medium text-foreground [overflow-wrap:anywhere]">
          <span className="sr-only">Completed task: </span>
          {task}
        </p>
      </div>
      {/* Lined up under the title, past the check. */}
      {note.taskDescription && (
        <p className="ml-[28px] mt-1 line-clamp-3 whitespace-pre-wrap text-sm leading-relaxed text-muted [overflow-wrap:anywhere]">
          {note.taskDescription}
        </p>
      )}

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

function NoteCard({
  note,
  author,
  onEdit,
  onDelete,
}: {
  note: NoteView;
  author: NoteAuthor;
  onEdit: (body: string) => void;
  onDelete: () => void;
}) {
  const [editing, setEditing] = useState(false);
  const [draft, setDraft] = useState(note.body);
  const [confirming, setConfirming] = useState(false);
  const pending = note.id.startsWith("pending-");
  const edited = new Date(note.updatedAt).getTime() - new Date(note.createdAt).getTime() > 1000;

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

      {/* Notes posted from "Done" on a suggestion say which one they complete. */}
      {note.completedSuggestion && (
        <p className="mt-3 flex items-start gap-1.5 text-sm font-medium text-muted">
          <HugeiconsIcon icon={CheckmarkCircle02Icon} size={16} className="mt-0.5 shrink-0 text-emerald-600 dark:text-emerald-400" />
          <span className="min-w-0 [text-wrap:pretty]">{note.completedSuggestion}</span>
        </p>
      )}

      {editing ? (
        <div className={note.completedSuggestion ? "mt-2" : "mt-3"}>
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
            className={`${textareaClass} [overflow-wrap:anywhere]`}
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
        <p className={`${note.completedSuggestion ? "mt-2" : "mt-3"} whitespace-pre-wrap text-[0.95rem] leading-relaxed text-foreground [overflow-wrap:anywhere]`}>
          {note.body}
        </p>
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
