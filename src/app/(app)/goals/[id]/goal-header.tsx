"use client";

import { Delete02Icon, PencilEdit02Icon, Refresh01Icon } from "@hugeicons/core-free-icons";
import { useRouter } from "next/navigation";
import { startTransition, useState, useTransition } from "react";

import { ConfirmDialog } from "@/components/confirm-dialog";
import { GoalBadge } from "@/components/goal-badge";
import { MoreMenu, MoreMenuItem } from "@/components/more-menu";
import { DEFAULT_GOAL_COLOR, isGoalColor } from "@/lib/goal-colors";
import { DEFAULT_GOAL_ICON, isGoalIcon } from "@/lib/goal-icons";
import type { GoalInput } from "@/lib/goal-schema";

import { deleteGoalAction, updateGoalAction } from "../actions";
import { GoalDialog } from "../goal-dialog";

type Goal = { id: string; title: string; icon: string; color: string };

type Props = {
  goal: Goal;
  /** Whether there are sources to read from. */
  canUpdate: boolean;
  reading: boolean;
  onUpdate: () => void;
};

export function GoalHeader({ goal, canUpdate, reading, onUpdate }: Props) {
  const router = useRouter();
  const [editing, setEditing] = useState(false);
  const [editKey, setEditKey] = useState(0);
  const [confirmingDelete, setConfirmingDelete] = useState(false);
  const [deleting, startDelete] = useTransition();
  const [error, setError] = useState<string | null>(null);

  const initial: GoalInput = {
    title: goal.title,
    icon: isGoalIcon(goal.icon) ? goal.icon : DEFAULT_GOAL_ICON,
    color: isGoalColor(goal.color) ? goal.color : DEFAULT_GOAL_COLOR,
  };

  return (
    <div>
      <div className="flex items-center justify-between gap-4">
        <GoalBadge icon={goal.icon} color={goal.color} size="lg" />
        <MoreMenu label="Goal options">
          <MoreMenuItem icon={Refresh01Icon} disabled={!canUpdate || reading} onSelect={onUpdate}>
            {reading ? "Updating…" : "Update status"}
          </MoreMenuItem>
          <MoreMenuItem
            icon={PencilEdit02Icon}
            onSelect={() => {
              setEditKey((k) => k + 1);
              setEditing(true);
            }}
          >
            Edit goal
          </MoreMenuItem>
          <MoreMenuItem icon={Delete02Icon} destructive onSelect={() => setConfirmingDelete(true)}>
            Delete goal
          </MoreMenuItem>
        </MoreMenu>
      </div>

      <h1 className="mt-5 text-2xl font-semibold leading-tight tracking-[-0.03em] text-foreground [text-wrap:balance] sm:text-3xl">
        {goal.title}
      </h1>
      {error && (
        <p role="alert" className="mt-4 text-sm text-red-600 dark:text-red-400">
          {error}
        </p>
      )}

      {editing && (
        <GoalDialog
          key={editKey}
          open
          onOpenChange={setEditing}
          mode="edit"
          initial={initial}
          onSave={(input) => {
            setEditing(false);
            startTransition(async () => {
              const result = await updateGoalAction(goal.id, input);
              setError(result.ok ? null : result.error);
            });
          }}
        />
      )}

      <ConfirmDialog
        open={confirmingDelete}
        onOpenChange={setConfirmingDelete}
        title="Delete this goal?"
        description="Its sources and progress read will be removed too. Your connected apps aren't affected."
        confirmLabel="Delete goal"
        pendingLabel="Deleting…"
        pending={deleting}
        onConfirm={() =>
          startDelete(async () => {
            const result = await deleteGoalAction(goal.id);
            if (result.ok) {
              router.push("/");
            } else {
              setConfirmingDelete(false);
              setError(result.error);
            }
          })
        }
      />
    </div>
  );
}
