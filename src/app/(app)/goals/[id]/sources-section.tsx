"use client";

import { Add01Icon, Delete02Icon, PencilEdit02Icon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import * as DropdownMenu from "@radix-ui/react-dropdown-menu";
import Link from "next/link";
import { useState, useTransition } from "react";

import { ConfirmDialog } from "@/components/confirm-dialog";
import { MoreMenu, MoreMenuItem } from "@/components/more-menu";
import { ProviderMark } from "@/components/provider-mark";
import { roundButtonClass } from "@/components/round-button";
import { PROVIDERS, type ProviderKey } from "@/lib/providers";
import type { SourceInput } from "@/lib/source-schema";

import { deleteSourceAction, saveSourceAction } from "./actions";
import { SourceDialog, type ConnectionOption, type GoalSummary } from "./source-dialog";

export type SourceView = {
  id: string;
  connectionId: string;
  provider: ProviderKey;
  relation: string;
  enabled: boolean;
  lastError: string | null;
};

type DialogState =
  | { mode: "create"; connection: ConnectionOption }
  | { mode: "edit"; source: SourceView }
  | null;

const addButtonClass = roundButtonClass;

/** "Add source": straight to the dialog with one connected app, otherwise pick the app first. */
function AddSourceButton({
  connections,
  onPick,
}: {
  connections: ConnectionOption[];
  onPick: (connection: ConnectionOption) => void;
}) {
  const content = <HugeiconsIcon icon={Add01Icon} size={18} />;

  if (connections.length === 1) {
    return (
      <button
        type="button"
        aria-label="Add source"
        title="Add source"
        onClick={() => onPick(connections[0])}
        className={addButtonClass}
      >
        {content}
      </button>
    );
  }

  return (
    <DropdownMenu.Root>
      <DropdownMenu.Trigger aria-label="Add source" title="Add source" className={addButtonClass}>
        {content}
      </DropdownMenu.Trigger>
      <DropdownMenu.Portal>
        <DropdownMenu.Content
          align="end"
          sideOffset={6}
          collisionPadding={12}
          className="z-50 w-52 rounded-xl border border-card-border bg-card p-1.5 shadow-[0_12px_32px_-12px_rgb(0_0_0/0.25)] outline-none data-[state=open]:animate-[pop-in_140ms_ease-out]"
        >
          {connections.map((c) => (
            <DropdownMenu.Item
              key={c.id}
              onSelect={() => onPick(c)}
              className="flex h-10 cursor-default select-none items-center gap-2.5 rounded-lg px-2.5 text-sm font-medium text-foreground outline-none data-[highlighted]:bg-wash"
            >
              <ProviderMark provider={c.provider} size="sm" />
              {PROVIDERS[c.provider].label}
            </DropdownMenu.Item>
          ))}
        </DropdownMenu.Content>
      </DropdownMenu.Portal>
    </DropdownMenu.Root>
  );
}

export function SourcesSection({
  goalId,
  goal,
  sources,
  connections,
}: {
  goalId: string;
  goal: GoalSummary;
  sources: SourceView[];
  connections: ConnectionOption[];
}) {
  const [dialog, setDialog] = useState<DialogState>(null);
  const [dialogKey, setDialogKey] = useState(0);
  const [dialogError, setDialogError] = useState<string | null>(null);
  const [saving, startSaving] = useTransition();

  function open(next: NonNullable<DialogState>) {
    setDialogError(null);
    setDialogKey((k) => k + 1);
    setDialog(next);
  }

  function save(input: SourceInput) {
    const sourceId = dialog?.mode === "edit" ? dialog.source.id : null;
    startSaving(async () => {
      const result = await saveSourceAction(goalId, sourceId, input);
      if (result.ok) setDialog(null);
      else setDialogError(result.error);
    });
  }

  return (
    <section aria-labelledby="sources-heading" className="mt-12">
      <div className="mb-4 flex items-center justify-between gap-4">
        <div>
          <h2 id="sources-heading" className="text-lg font-semibold tracking-[-0.02em] text-foreground">
            Sources
          </h2>
          <p className="text-sm text-muted">Where context for this goal lives, and how it relates.</p>
        </div>
        {connections.length > 0 && (
          <AddSourceButton connections={connections} onPick={(connection) => open({ mode: "create", connection })} />
        )}
      </div>

      {connections.length === 0 ? (
        <div className="rounded-2xl border border-dashed border-foreground/15 p-6 text-sm leading-relaxed text-muted">
          Connect Linear, GitHub or Granola first, then tell Supervibes where this goal&apos;s context lives.{" "}
          <Link href="/connections" className="font-semibold text-foreground underline-offset-4 hover:underline">
            Go to Connections
          </Link>
        </div>
      ) : sources.length === 0 ? (
        <p className="rounded-2xl border border-dashed border-foreground/15 p-6 text-sm leading-relaxed text-muted">
          No sources yet. Add one and describe, in your own words, where to look and how it relates to this goal.
        </p>
      ) : (
        <ul className="divide-y divide-card-border overflow-hidden rounded-2xl border border-card-border bg-card">
          {sources.map((source) => (
            <SourceRow key={source.id} source={source} onEdit={() => open({ mode: "edit", source })} />
          ))}
        </ul>
      )}

      {dialog && (
        <SourceDialog
          key={dialogKey}
          goal={goal}
          connection={
            dialog.mode === "edit"
              ? { id: dialog.source.connectionId, provider: dialog.source.provider }
              : dialog.connection
          }
          initialRelation={dialog.mode === "edit" ? dialog.source.relation : ""}
          mode={dialog.mode}
          pending={saving}
          error={dialogError}
          onOpenChange={(isOpen) => !isOpen && setDialog(null)}
          onSave={save}
        />
      )}
    </section>
  );
}

function SourceRow({ source, onEdit }: { source: SourceView; onEdit: () => void }) {
  const [deleting, startDelete] = useTransition();
  const [confirming, setConfirming] = useState(false);
  const label = PROVIDERS[source.provider].label;

  return (
    <li className={`flex items-center gap-4 px-4 py-3.5 sm:px-5 ${deleting ? "opacity-50" : ""}`}>
      <ProviderMark provider={source.provider} />

      <div className="min-w-0 flex-1">
        <p className="text-sm font-semibold text-foreground">{label}</p>
        <p className="truncate text-sm text-muted" title={source.relation}>
          {source.relation}
        </p>
      </div>

      {source.lastError && (
        <Link
          href="/connections"
          title={source.lastError}
          className="hidden shrink-0 text-xs font-medium text-red-600 underline-offset-4 hover:underline sm:block dark:text-red-400"
        >
          Needs reconnecting
        </Link>
      )}

      <MoreMenu label={`${label} source options`}>
        <MoreMenuItem icon={PencilEdit02Icon} onSelect={onEdit}>
          Edit
        </MoreMenuItem>
        <MoreMenuItem icon={Delete02Icon} destructive onSelect={() => setConfirming(true)}>
          Delete
        </MoreMenuItem>
      </MoreMenu>

      <ConfirmDialog
        open={confirming}
        onOpenChange={setConfirming}
        title={`Remove this ${label} source?`}
        description="Future progress reads won't look here anymore. The app itself stays connected."
        confirmLabel="Remove"
        pendingLabel="Removing…"
        pending={deleting}
        onConfirm={() =>
          startDelete(async () => {
            await deleteSourceAction(source.id);
            setConfirming(false);
          })
        }
      />
    </li>
  );
}
