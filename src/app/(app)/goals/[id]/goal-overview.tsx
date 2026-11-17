"use client";

import { useState, useTransition } from "react";

import { refreshProgressAction } from "./actions";
import { GoalHeader } from "./goal-header";
import { ProgressCard, type ReadView } from "./progress-card";

type Props = {
  goal: { id: string; title: string; icon: string; color: string };
  read: ReadView | null;
  hasSources: boolean;
};

/** Goal header and progress card, sharing one "reading progress" state. */
export function GoalOverview({ goal, read, hasSources }: Props) {
  const [reading, startReading] = useTransition();
  const [error, setError] = useState<string | null>(null);

  function update() {
    setError(null);
    startReading(async () => {
      const result = await refreshProgressAction(goal.id);
      if (!result.ok) setError(result.error);
    });
  }

  return (
    <>
      <GoalHeader goal={goal} canUpdate={hasSources} reading={reading} onUpdate={update} />
      <ProgressCard read={read} hasSources={hasSources} reading={reading} error={error} onUpdate={update} />
    </>
  );
}
