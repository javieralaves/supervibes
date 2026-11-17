"use client";

import { CheckListIcon, Note01Icon, Refresh01Icon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";

import { ProviderMark } from "@/components/provider-mark";
import { PROVIDERS, toProvider, type ProviderKey } from "@/lib/providers";
import { shortAgo } from "@/lib/time";

export type ReadView = {
  headline: string;
  summary: string;
  basedOn: string[];
  createdAt: string;
};

type Props = {
  read: ReadView | null;
  /** There's something to read: at least one source or note. */
  canRead: boolean;
  /** A read is in progress (started here or from the goal's menu). */
  reading: boolean;
  error: string | null;
  onUpdate: () => void;
};

/** The single high-level read of progress on a goal, above its sources. */
export function ProgressCard({ read, canRead, reading, error, onUpdate }: Props) {
  const note = reading ? "Reading your sources. This can take a minute." : error;
  const noteEl = note && (
    <p role="status" className={`text-xs ${error && !reading ? "text-red-600 dark:text-red-400" : "text-muted"}`}>
      {note}
    </p>
  );

  if (!read) {
    return (
      <section aria-labelledby="progress-heading" aria-busy={reading} className="mt-10 rounded-2xl border border-card-border bg-card p-5 sm:p-6">
        <h2 id="progress-heading" className="text-lg font-semibold tracking-[-0.02em] text-foreground">
          {canRead ? "Ready for a first read" : "No read yet"}
        </h2>
        <p className="mt-1 text-sm leading-relaxed text-muted">
          {canRead
            ? "Supervibes will look at your tasks, notes and sources and tell you, in a few lines, whether you're moving forward."
            : "Add a task, a note or a source below. Supervibes will read them and tell you, in a few lines, whether you're moving forward."}
        </p>
        {canRead && (
          <button
            type="button"
            onClick={onUpdate}
            disabled={reading}
            className="mt-5 flex h-9 items-center gap-1.5 rounded-xl border border-card-border px-3 text-sm font-medium text-foreground transition-colors hover:border-line-strong disabled:opacity-60"
          >
            <HugeiconsIcon icon={Refresh01Icon} size={15} className={reading ? "animate-spin" : ""} />
            {reading ? "Reading…" : "Update status"}
          </button>
        )}
        {noteEl && <div className="mt-3">{noteEl}</div>}
      </section>
    );
  }

  const apps = [...new Set(read.basedOn.map(toProvider).filter((p): p is ProviderKey => p !== null))];
  const usedNotes = read.basedOn.includes("notes");
  const usedTasks = read.basedOn.includes("tasks");
  const basedOnLabel = [
    ...apps.map((a) => PROVIDERS[a].label),
    ...(usedNotes ? ["your notes"] : []),
    ...(usedTasks ? ["your tasks"] : []),
  ].join(", ");

  return (
    <section
      aria-labelledby="progress-heading"
      aria-busy={reading}
      className="mt-10 rounded-2xl border border-card-border bg-card p-5 sm:p-6"
    >
      <div className={`transition-opacity ${reading ? "opacity-50" : ""}`}>
        <h2
          id="progress-heading"
          className="text-xl font-semibold leading-snug tracking-[-0.02em] text-foreground [text-wrap:balance]"
        >
          {read.headline}
        </h2>
        <p className="mt-2 text-[0.95rem] leading-relaxed text-muted [text-wrap:pretty]">{read.summary}</p>
      </div>

      <div className="mt-5 flex flex-wrap items-center gap-x-3 gap-y-1 text-xs text-muted">
        <p className="flex items-center gap-2">
          {basedOnLabel && (
            <span role="img" className="flex items-center gap-1" aria-label={`Based on ${basedOnLabel}`}>
              {apps.map((app) => (
                <ProviderMark key={app} provider={app} size="xs" />
              ))}
              {usedNotes && (
                <span className="inline-flex h-[18px] w-[18px] items-center justify-center rounded-[5px] border border-card-border bg-wash text-foreground">
                  <HugeiconsIcon icon={Note01Icon} size={11} />
                </span>
              )}
              {usedTasks && (
                <span className="inline-flex h-[18px] w-[18px] items-center justify-center rounded-[5px] border border-card-border bg-wash text-foreground">
                  <HugeiconsIcon icon={CheckListIcon} size={11} />
                </span>
              )}
            </span>
          )}
          <span suppressHydrationWarning>{shortAgo(read.createdAt)}</span>
        </p>
        {reading && <HugeiconsIcon icon={Refresh01Icon} size={13} className="animate-spin" />}
        {noteEl}
      </div>
    </section>
  );
}
