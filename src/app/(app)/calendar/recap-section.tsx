"use client";

import { ArrowRight01Icon, Refresh01Icon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import Link from "next/link";
import { useLayoutEffect, useRef, useState, useTransition } from "react";

import { Breadcrumbs } from "@/components/breadcrumbs";
import type { BlockView } from "@/lib/block-schema";
import { MAX_POST } from "@/lib/post-schema";
import type { BlockRecap, PostedRecap } from "@/lib/recap-schema";

import { discardRecapAction, postRecapAction, prepareRecapAction } from "./actions";

/**
 * "Recap session", once a block has ended: a draft of what was meant to happen
 * and what did, from the goal's connected apps, that the person edits and posts
 * to the goal's activity. With no apps to read, it's an empty write-up. Once
 * posted, the recap itself shows here, as the record of how the session went.
 */
export function RecapSection({ block }: { block: BlockView }) {
  const [fresh, setFresh] = useState<BlockRecap | null>(null);
  // Set after discarding, until the calendar catches up.
  const [cleared, setCleared] = useState(false);
  // What was just posted here, until the calendar catches up with it.
  const [posted, setPosted] = useState<PostedRecap | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [preparing, startPreparing] = useTransition();

  const saved = block.recap;
  const latest = fresh && (!saved || fresh.preparedAt > saved.preparedAt) ? fresh : saved;
  const recap = cleared ? null : latest;

  function prepare() {
    setError(null);
    startPreparing(async () => {
      const result = await prepareRecapAction(block.id);
      if (result.ok) {
        setFresh(result.recap);
        setCleared(false);
      } else {
        setError(result.error);
      }
    });
  }

  const shown = block.recapPost ?? posted;
  if (shown) return <PostedRecapView goalId={block.goalId} recap={shown} />;

  return (
    <section aria-label="Recap" className="mt-6">
      {preparing && !recap ? (
        <div aria-label="Recapping session">
          <p className="text-[13px] text-muted">Looking through your connected apps…</p>
          <div className="mt-3 space-y-2">
            {["w-full", "w-[90%]", "w-full", "w-2/3"].map((w, i) => (
              <div key={i} className={`h-3 animate-pulse rounded bg-foreground/[.07] ${w}`} />
            ))}
          </div>
        </div>
      ) : recap ? (
        <RecapDraft
          // A fresh draft resets what's being edited.
          key={recap.preparedAt}
          block={block}
          recap={recap}
          preparing={preparing}
          onRedraft={prepare}
          onPosted={setPosted}
          onDiscarded={() => {
            setFresh(null);
            setCleared(true);
          }}
        />
      ) : (
        <button
          type="button"
          onClick={prepare}
          title="Draft what happened in this session from the goal's connected apps"
          className="flex h-9 w-full items-center justify-center rounded-lg bg-foreground px-3 text-sm font-semibold text-background transition-opacity hover:opacity-90"
        >
          Recap session
        </button>
      )}
      {error && (
        <p role="alert" className="mt-2 text-sm text-red-600 dark:text-red-400">
          {error}
        </p>
      )}
    </section>
  );
}

const FOUND_HINT: Record<BlockRecap["found"], string> = {
  clear: "Drafted from your connected apps. Edit anything before posting.",
  partial: "Drafted from what your connected apps show. Fill in the rest.",
  none: "Nothing in your connected apps from this session. Write what happened.",
  "no-sources": "This goal has no connected apps. Write what happened.",
};

function RecapDraft({
  block,
  recap,
  preparing,
  onRedraft,
  onPosted,
  onDiscarded,
}: {
  block: BlockView;
  recap: BlockRecap;
  preparing: boolean;
  onRedraft: () => void;
  onPosted: (recap: PostedRecap) => void;
  onDiscarded: () => void;
}) {
  const [text, setText] = useState(recap.happened);
  const [removed, setRemoved] = useState<Set<string>>(new Set());
  const [markDone, setMarkDone] = useState(recap.taskLooksDone);
  const [error, setError] = useState<string | null>(null);
  const [saving, startSaving] = useTransition();

  const kept = recap.breadcrumbs.filter((b) => !removed.has(b.url));
  const canMarkDone = Boolean(block.taskId) && !block.taskDone;
  const busy = saving || preparing;

  function post() {
    setError(null);
    startSaving(async () => {
      const result = await postRecapAction(block.id, {
        body: text,
        keep: kept.map((b) => b.url),
        markTaskDone: canMarkDone && markDone,
      });
      if (result.ok) onPosted({ body: text.trim(), breadcrumbs: kept });
      else setError(result.error);
    });
  }

  function discard() {
    setError(null);
    startSaving(async () => {
      const result = await discardRecapAction(block.id);
      if (result.ok) onDiscarded();
      else setError(result.error);
    });
  }

  return (
    <div className={preparing ? "opacity-50" : undefined}>
      <div className="flex items-baseline justify-between gap-2">
        <h3 className="text-[13px] font-semibold text-foreground">Recap</h3>
        {recap.found !== "no-sources" && (
          <button
            type="button"
            onClick={onRedraft}
            disabled={busy}
            className="-mr-2 flex h-7 items-center gap-1.5 rounded-lg px-2 text-xs font-medium text-muted transition-colors hover:bg-wash hover:text-foreground disabled:opacity-60"
          >
            <HugeiconsIcon icon={Refresh01Icon} size={13} className={preparing ? "animate-spin" : undefined} />
            {preparing ? "Drafting…" : "Draft again"}
          </button>
        )}
      </div>
      <p className="mt-0.5 text-xs leading-relaxed text-muted [text-wrap:pretty]">{FOUND_HINT[recap.found]}</p>

      {recap.planned && (
        <p className="mt-3 text-[13px] leading-snug text-muted [text-wrap:pretty]">
          <span className="font-medium text-foreground/70">Planned:</span> {recap.planned}
        </p>
      )}

      <label className="sr-only" htmlFor={`recap-${block.id}`}>
        What happened
      </label>
      <textarea
        id={`recap-${block.id}`}
        value={text}
        maxLength={MAX_POST}
        rows={4}
        autoFocus={!recap.happened}
        onChange={(e) => {
          setText(e.target.value);
          setError(null);
        }}
        onKeyDown={(e) => {
          if (e.key === "Enter" && (e.metaKey || e.ctrlKey) && text.trim()) {
            e.preventDefault();
            post();
          }
        }}
        placeholder="What happened in this session?"
        className="mt-2 block max-h-80 min-h-24 w-full resize-none rounded-xl border border-card-border bg-background/60 px-3 py-2.5 text-sm leading-relaxed text-foreground outline-none transition-colors [field-sizing:content] placeholder:text-muted/80 focus:border-line-strong"
      />

      <Breadcrumbs
        items={kept}
        onRemove={(url) => setRemoved((s) => new Set(s).add(url))}
        className="mt-2"
      />

      {canMarkDone && (
        <label className="mt-3 flex cursor-pointer items-center gap-2 text-[13px] text-foreground">
          <input
            type="checkbox"
            checked={markDone}
            onChange={(e) => setMarkDone(e.target.checked)}
            className="h-4 w-4 accent-[var(--foreground)]"
          />
          Also mark the task done
        </label>
      )}

      {error && (
        <p role="alert" className="mt-2 text-sm text-red-600 dark:text-red-400">
          {error}
        </p>
      )}

      <div className="mt-4 flex gap-2">
        <button
          type="button"
          onClick={discard}
          disabled={busy}
          className="h-9 rounded-lg px-3 text-sm font-medium text-muted transition-colors hover:bg-wash hover:text-foreground disabled:opacity-60"
        >
          Discard
        </button>
        <button
          type="button"
          onClick={post}
          disabled={busy || !text.trim()}
          className="h-9 flex-1 rounded-lg bg-foreground px-3 text-sm font-semibold text-background transition-opacity hover:opacity-90 disabled:opacity-30"
        >
          {saving ? "Posting…" : "Post to activity"}
        </button>
      </div>
    </div>
  );
}

/** A posted recap: what happened, clamped until asked for in full, and the links it kept. */
function PostedRecapView({ goalId, recap }: { goalId: string; recap: PostedRecap }) {
  const [expanded, setExpanded] = useState(false);
  const [clamped, setClamped] = useState(false);
  const body = useRef<HTMLParagraphElement>(null);

  // Only offer "Show more" when the clamp is actually hiding something.
  useLayoutEffect(() => {
    const el = body.current;
    if (el && !expanded) setClamped(el.scrollHeight > el.clientHeight + 1);
  }, [recap.body, expanded]);

  return (
    <section aria-label="Recap" className="mt-6">
      <div className="flex items-baseline justify-between gap-2">
        <h3 className="text-[13px] font-semibold text-foreground">Recap</h3>
        <Link
          href={`/goals/${goalId}`}
          className="flex items-center gap-0.5 self-center text-xs font-medium text-muted transition-colors hover:text-foreground"
        >
          View in goal
          <HugeiconsIcon icon={ArrowRight01Icon} size={13} />
        </Link>
      </div>
      {recap.body && (
        <>
          <p
            ref={body}
            className={`mt-1.5 whitespace-pre-wrap text-sm leading-relaxed text-foreground/90 [overflow-wrap:anywhere] [text-wrap:pretty] ${
              expanded ? "" : "line-clamp-4"
            }`}
          >
            {recap.body}
          </p>
          {(clamped || expanded) && (
            <button
              type="button"
              onClick={() => setExpanded((e) => !e)}
              aria-expanded={expanded}
              className="mt-1 text-xs font-medium text-muted transition-colors hover:text-foreground"
            >
              {expanded ? "Show less" : "Show more"}
            </button>
          )}
        </>
      )}
      <Breadcrumbs items={recap.breadcrumbs} className="mt-2" />
    </section>
  );
}
