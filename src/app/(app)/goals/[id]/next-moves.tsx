"use client";

import { Clock01Icon, Tick02Icon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import { startTransition, useOptimistic, useState } from "react";

import { MAX_POST, postBodySchema } from "@/lib/post-schema";

import { completeSuggestionAction, passOnSuggestionAction } from "./actions";

export type SuggestionView = { title: string; why: string; minutes: number };

function sizeLabel(minutes: number) {
  return minutes >= 120 ? "2 hr" : minutes >= 60 ? "1 hr" : "30 min";
}

/** 2–3 concrete things to do next, refreshed with every progress read. */
export function NextMoves({
  goalId,
  suggestions,
  reading,
  onDone,
}: {
  goalId: string;
  suggestions: SuggestionView[];
  reading: boolean;
  /** Called once the last remaining suggestion is marked done, to refresh the read. */
  onDone: () => void;
}) {
  const [visible, hide] = useOptimistic(suggestions, (list: SuggestionView[], title: string) =>
    list.filter((s) => s.title !== title),
  );
  const [error, setError] = useState<string | null>(null);

  function finish(title: string, done: boolean, note?: string) {
    setError(null);
    // Only refresh the read once the final suggestion is marked done, not after each one.
    const isLast = visible.filter((s) => s.title !== title).length === 0;
    startTransition(async () => {
      hide(title);
      const result = done
        ? await completeSuggestionAction(goalId, title, note)
        : await passOnSuggestionAction(goalId, title);
      if (!result.ok) setError(result.error);
      else if (done && isLast) onDone();
    });
  }

  return (
    <section aria-labelledby="next-moves-heading" aria-busy={reading} className="mt-12">
      <div className="mb-4">
        <h2 id="next-moves-heading" className="text-lg font-semibold tracking-[-0.02em] text-foreground">
          Suggestions
        </h2>
        <p className="text-sm text-muted">Things you could do to make progress on your goal.</p>
      </div>

      {error && (
        <p role="alert" className="mb-3 text-sm text-red-600 dark:text-red-400">
          {error}
        </p>
      )}

      {visible.length === 0 ? (
        <p className="rounded-2xl border border-dashed border-foreground/15 p-5 text-sm text-muted">
          {reading ? "Working out what's next…" : "Nothing left for now. Fresh suggestions come with the next status update."}
        </p>
      ) : (
        <ul className={`grid gap-3 transition-opacity ${reading ? "opacity-50" : ""}`}>
          {visible.map((s) => (
            <SuggestionCard
              key={s.title}
              suggestion={s}
              disabled={reading}
              onPost={(note) => finish(s.title, true, note)}
              onPass={() => finish(s.title, false)}
            />
          ))}
        </ul>
      )}
    </section>
  );
}

function SuggestionCard({
  suggestion,
  disabled,
  onPost,
  onPass,
}: {
  suggestion: SuggestionView;
  disabled: boolean;
  onPost: (note: string) => void;
  onPass: () => void;
}) {
  // "Done" opens a note to edit before it's posted; nothing is saved until Post.
  const [writing, setWriting] = useState(false);
  const [draft, setDraft] = useState("");
  const noteId = `done-${suggestion.title}`;

  function post() {
    const parsed = postBodySchema.safeParse(draft);
    if (!parsed.success) return;
    onPost(parsed.data);
  }

  return (
    <li
      className={`rounded-2xl border bg-card p-4 transition-[border-color,box-shadow] sm:p-5 ${
        writing
          ? "border-line-strong shadow-[0_0_0_4px_color-mix(in_oklab,var(--foreground)_6%,transparent)]"
          : "border-card-border"
      }`}
    >
      <div className="flex flex-col gap-4 sm:flex-row sm:items-center sm:gap-6">
        <div className="min-w-0 flex-1">
          <span className="inline-flex w-fit items-center gap-1 rounded-full border border-card-border px-2 py-0.5 text-[11px] font-medium text-muted">
            <HugeiconsIcon icon={Clock01Icon} size={12} />
            {sizeLabel(suggestion.minutes)}
          </span>
          <p className="mt-2.5 font-semibold leading-snug tracking-[-0.01em] text-foreground [text-wrap:pretty]">
            {suggestion.title}
          </p>
          <p className="mt-1 text-sm leading-relaxed text-muted [text-wrap:pretty]">{suggestion.why}</p>
        </div>

        {!writing && (
          <div className="flex shrink-0 items-center gap-1.5">
            <button
              type="button"
              disabled={disabled}
              onClick={() => {
                setDraft("");
                setWriting(true);
              }}
              className="flex h-8 items-center gap-1.5 rounded-lg border border-card-border bg-card px-2.5 text-sm font-medium text-foreground shadow-[0_1px_2px_rgb(15_17_20/0.05)] transition-colors hover:border-line-strong disabled:opacity-50"
            >
              <HugeiconsIcon icon={Tick02Icon} size={14} />
              Done
            </button>
            <button
              type="button"
              disabled={disabled}
              onClick={onPass}
              className="h-8 rounded-lg px-2.5 text-sm font-medium text-muted transition-colors hover:bg-wash hover:text-foreground disabled:opacity-50"
            >
              Not now
            </button>
          </div>
        )}
      </div>

      {writing && (
        <div className="mt-4 border-t border-card-border pt-4">
          <label htmlFor={noteId} className="text-xs font-medium text-muted">
            Add a note about what you did
          </label>
          <textarea
            id={noteId}
            autoFocus
            rows={2}
            value={draft}
            maxLength={MAX_POST}
            placeholder="What did you do? Anything worth remembering?"
            onChange={(e) => setDraft(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === "Enter" && (e.metaKey || e.ctrlKey)) {
                e.preventDefault();
                post();
              }
              if (e.key === "Escape") setWriting(false);
            }}
            className="mt-1.5 block w-full resize-none bg-transparent text-[0.95rem] leading-relaxed text-foreground outline-none [field-sizing:content] [overflow-wrap:anywhere] placeholder:text-muted/80"
          />
          <div className="mt-3 flex items-center justify-between gap-3">
            <p className="hidden text-xs text-muted sm:block">⌘↵ to post · Esc to cancel</p>
            <div className="ml-auto flex gap-1.5">
              <button
                type="button"
                onClick={() => setWriting(false)}
                className="h-8 rounded-lg px-3 text-sm font-medium text-muted hover:bg-wash hover:text-foreground"
              >
                Cancel
              </button>
              <button
                type="button"
                onClick={post}
                disabled={disabled || !draft.trim()}
                className="h-8 rounded-lg bg-foreground px-3 text-sm font-semibold text-background hover:opacity-90 disabled:opacity-30"
              >
                Post
              </button>
            </div>
          </div>
        </div>
      )}
    </li>
  );
}
