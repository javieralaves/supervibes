"use client";

import { useState, useTransition } from "react";

import { formatWeek } from "@/lib/target-date";
import { MAX_WEEK_OBJECTIVE } from "@/lib/week-objective-schema";

import { setWeekObjectiveAction } from "./actions";

/**
 * "This week": what the week should move for this goal, in the person's words.
 * Optional, and saved when the field loses focus. Progress reads judge the week
 * against it, agendas steer by it, and recaps say whether a session moved it.
 * Last week's, if there was one, sits under an empty field for continuity.
 */
export function WeekObjective({
  goalId,
  weekStart,
  saved,
  lastWeek,
}: {
  goalId: string;
  /** The Monday this week starts on, "YYYY-MM-DD", in the person's own calendar. */
  weekStart: string;
  saved: string | null;
  lastWeek: string | null;
}) {
  const [draft, setDraft] = useState(saved ?? "");
  const [error, setError] = useState<string | null>(null);
  const [saving, startSaving] = useTransition();

  function save() {
    const value = draft.trim();
    if (value === (saved ?? "")) return;
    setError(null);
    startSaving(async () => {
      const result = await setWeekObjectiveAction(goalId, weekStart, value);
      if (!result.ok) setError(result.error);
    });
  }

  return (
    <section aria-labelledby="week-heading" className="mt-8">
      <div className="flex items-baseline gap-2">
        <h2 id="week-heading" className="text-[13px] font-semibold text-foreground">
          This week
        </h2>
        <span className="text-xs tabular-nums text-muted">{formatWeek(weekStart)}</span>
        {saving && <span className="text-xs text-muted">Saving…</span>}
      </div>
      <textarea
        aria-label="What this week should move for this goal"
        value={draft}
        maxLength={MAX_WEEK_OBJECTIVE}
        rows={1}
        onChange={(e) => setDraft(e.target.value)}
        onBlur={save}
        onKeyDown={(e) => {
          if (e.key === "Enter" && (e.metaKey || e.ctrlKey)) e.currentTarget.blur();
          if (e.key === "Escape") {
            setDraft(saved ?? "");
            requestAnimationFrame(() => (e.target as HTMLTextAreaElement).blur());
          }
        }}
        placeholder="What should this week move for this goal? (optional)"
        title="Progress reads judge the week against it, and agendas and recaps take it into account"
        className="-mx-2 mt-1 block w-[calc(100%+1rem)] max-w-2xl resize-none rounded-lg bg-transparent px-2 py-1.5 text-[0.95rem] leading-relaxed text-foreground/90 outline-none transition-colors [field-sizing:content] placeholder:text-muted/70 hover:bg-wash/60 focus:bg-wash/60"
      />
      {lastWeek && !draft.trim() && (
        <p className="mt-0.5 line-clamp-2 max-w-2xl text-xs leading-relaxed text-muted">
          <span className="font-medium">Last week:</span> {lastWeek}
        </p>
      )}
      {error && (
        <p role="alert" className="mt-1 text-sm text-red-600 dark:text-red-400">
          {error}
        </p>
      )}
    </section>
  );
}
