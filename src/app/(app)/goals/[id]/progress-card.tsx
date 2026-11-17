"use client";

import { Refresh01Icon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";

import { ProviderMark } from "@/components/provider-mark";
import { PROVIDERS, toProvider, type ProviderKey } from "@/lib/providers";

export type ReadView = {
  headline: string;
  summary: string;
  basedOn: string[];
  createdAt: string;
};

/** Compact relative time: "just now", "3 min ago", "2 hr ago", "4 days ago". */
function ago(iso: string) {
  const minutes = Math.max(0, Math.round((Date.now() - new Date(iso).getTime()) / 60000));
  if (minutes < 1) return "just now";
  if (minutes < 60) return `${minutes} min ago`;
  const hours = Math.round(minutes / 60);
  if (hours < 24) return `${hours} hr ago`;
  const days = Math.round(hours / 24);
  return `${days} ${days === 1 ? "day" : "days"} ago`;
}

type Props = {
  read: ReadView | null;
  hasSources: boolean;
  /** A read is in progress (started here or from the goal's menu). */
  reading: boolean;
  error: string | null;
  onUpdate: () => void;
};

/** The single high-level read of progress on a goal, above its sources. */
export function ProgressCard({ read, hasSources, reading, error, onUpdate }: Props) {
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
          {hasSources ? "Ready for a first read" : "No read yet"}
        </h2>
        <p className="mt-1 text-sm leading-relaxed text-muted">
          {hasSources
            ? "Supervibes will look at everything your sources show and tell you, in a few lines, whether you're moving forward."
            : "Add a source below. Supervibes will read it and tell you, in a few lines, whether you're moving forward."}
        </p>
        {hasSources && (
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
          {apps.length > 0 && (
            <span
              role="img"
              className="flex items-center gap-1"
              aria-label={`Based on ${apps.map((a) => PROVIDERS[a].label).join(", ")}`}
            >
              {apps.map((app) => (
                <ProviderMark key={app} provider={app} size="xs" />
              ))}
            </span>
          )}
          <span suppressHydrationWarning>{ago(read.createdAt)}</span>
        </p>
        {reading && <HugeiconsIcon icon={Refresh01Icon} size={13} className="animate-spin" />}
        {noteEl}
      </div>
    </section>
  );
}
