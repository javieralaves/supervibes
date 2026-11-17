"use client";

import { Cancel01Icon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import * as Dialog from "@radix-ui/react-dialog";
import { useId, useState } from "react";

import { GoalBadge } from "@/components/goal-badge";
import { ProviderMark } from "@/components/provider-mark";
import { PROVIDERS, type ProviderKey } from "@/lib/providers";
import { MAX_RELATION, sourceInputSchema, type SourceInput } from "@/lib/source-schema";

export type ConnectionOption = { id: string; provider: ProviderKey };
export type GoalSummary = { title: string; icon: string; color: string };

type Props = {
  goal: GoalSummary;
  connection: ConnectionOption;
  initialRelation: string;
  mode: "create" | "edit";
  pending: boolean;
  error: string | null;
  onOpenChange: (open: boolean) => void;
  onSave: (input: SourceInput) => void;
};

export function SourceDialog({ goal, connection, initialRelation, mode, pending, error, onOpenChange, onSave }: Props) {
  const [relation, setRelation] = useState(initialRelation);
  const [localError, setLocalError] = useState<string | null>(null);
  const fieldId = useId();
  const app = PROVIDERS[connection.provider];

  function submit(event: React.FormEvent) {
    event.preventDefault();
    const parsed = sourceInputSchema.safeParse({ connectionId: connection.id, relation });
    if (!parsed.success) {
      setLocalError(parsed.error.issues[0]?.message ?? "Check the form.");
      return;
    }
    setLocalError(null);
    onSave(parsed.data);
  }

  const shownError = localError ?? error;

  return (
    <Dialog.Root open onOpenChange={onOpenChange}>
      <Dialog.Portal>
        <Dialog.Overlay className="fixed inset-0 z-40 bg-black/40 data-[state=open]:animate-[fade-in_150ms_ease-out]" />
        <Dialog.Content
          aria-describedby={undefined}
          className="fixed inset-x-0 bottom-0 z-50 flex max-h-[92dvh] flex-col rounded-t-[20px] border border-card-border bg-background shadow-2xl outline-none data-[state=open]:animate-[sheet-in_220ms_cubic-bezier(0.2,0.7,0.2,1)] sm:inset-x-auto sm:bottom-auto sm:left-1/2 sm:top-1/2 sm:max-h-[88dvh] sm:w-[480px] sm:-translate-x-1/2 sm:-translate-y-1/2 sm:rounded-[20px] sm:data-[state=open]:animate-[pop-in_180ms_cubic-bezier(0.2,0.7,0.2,1)]"
        >
          <form onSubmit={submit} className="flex min-h-0 flex-1 flex-col">
            <div className="min-h-0 flex-1 overflow-y-auto px-6 pb-6 pt-6">
              <div className="flex items-start justify-between">
                {/* The goal, with the app it's linking to tucked into the corner. */}
                <span className="relative inline-flex">
                  <GoalBadge icon={goal.icon} color={goal.color} size="lg" />
                  <span className="absolute -bottom-1.5 -right-1.5 rounded-[9px] ring-[3px] ring-background">
                    <ProviderMark provider={connection.provider} size="sm" />
                  </span>
                </span>
                <Dialog.Close
                  aria-label="Close"
                  className="-mr-2 -mt-1 flex h-9 w-9 items-center justify-center rounded-full text-muted transition-colors hover:bg-wash hover:text-foreground"
                >
                  <HugeiconsIcon icon={Cancel01Icon} size={18} />
                </Dialog.Close>
              </div>

              <Dialog.Title className="mt-5 text-lg font-semibold tracking-[-0.02em] text-foreground">
                {mode === "create" ? "Add a source" : "Edit source"}
              </Dialog.Title>
              <p className="mt-1 text-sm text-muted [text-wrap:pretty]">For “{goal.title}”</p>

              <label htmlFor={fieldId} className="mt-6 block text-sm font-medium text-foreground">
                How does {app.label} relate to this goal?
              </label>
              <p className="mt-1 text-sm text-muted">Where to look, what counts, and what to ignore.</p>
              <textarea
                id={fieldId}
                autoFocus
                rows={6}
                value={relation}
                maxLength={MAX_RELATION}
                onChange={(e) => {
                  setRelation(e.target.value);
                  setLocalError(null);
                }}
                placeholder={app.relationHint}
                className="mt-3 w-full resize-none rounded-xl border border-card-border bg-card px-3.5 py-3 text-sm leading-relaxed text-foreground outline-none transition-colors placeholder:text-muted/80 focus:border-line-strong"
              />
              {shownError && (
                <p role="alert" className="mt-2 text-sm text-red-600 dark:text-red-400">
                  {shownError}
                </p>
              )}
            </div>

            <div className="flex justify-end gap-2 border-t border-card-border px-6 py-4 pb-[max(1rem,env(safe-area-inset-bottom))]">
              <Dialog.Close className="h-10 rounded-xl px-4 text-sm font-medium text-foreground transition-colors hover:bg-wash">
                Cancel
              </Dialog.Close>
              <button
                type="submit"
                disabled={pending}
                className="h-10 rounded-xl bg-foreground px-5 text-sm font-semibold text-background transition-opacity hover:opacity-90 disabled:opacity-60"
              >
                {pending ? "Saving…" : mode === "create" ? "Add source" : "Save"}
              </button>
            </div>
          </form>
        </Dialog.Content>
      </Dialog.Portal>
    </Dialog.Root>
  );
}
