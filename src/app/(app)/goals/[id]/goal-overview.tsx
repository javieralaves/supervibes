"use client";

import { useRouter } from "next/navigation";
import { useEffect, useState, useTransition } from "react";

import type { Clock } from "@/lib/settings-schema";

import { refreshProgressAction } from "./actions";
import { GoalHeader } from "./goal-header";
import { NotesSection, type NoteAuthor, type NoteView } from "./notes-section";
import { ProgressCard, type ReadView } from "./progress-card";
import type { ConnectionOption } from "./source-dialog";
import { SourcesSection, type SourceView } from "./sources-section";
import { TasksSection, type SuggestionView, type TaskView } from "./tasks-section";
import { WeekObjective } from "./week-objective";

type Props = {
  goal: { id: string; title: string; description: string | null; targetDate: string | null; icon: string; color: string };
  read: (ReadView & { suggestions: SuggestionView[] }) | null;
  /** Whether a progress read is running in the background. */
  readPending: boolean;
  /** Why the last background read failed, if it did. */
  readError: string | null;
  notes: NoteView[];
  author: NoteAuthor;
  tasks: TaskView[];
  /** The user's clock choice, for times like when a task is scheduled. */
  clock: Clock | null;
  /** The person's today, "YYYY-MM-DD". */
  today: string;
  /** This week's objective for the goal, and last week's, by the Monday each starts on. */
  week: { start: string; objective: string | null; lastWeek: string | null };
  sources: SourceView[];
  /** Connected apps a new source can read from. */
  connections: ConnectionOption[];
};

/** Goal header, progress read, tasks and suggestions, sources and activity, sharing one "reading progress" state. */
/** How often to check whether a background read has landed. */
const POLL_MS = 4_000;

export function GoalOverview({
  goal,
  read,
  readPending,
  readError,
  notes,
  author,
  tasks,
  clock,
  today,
  week,
  sources,
  connections,
}: Props) {
  const router = useRouter();
  const [requesting, startRequesting] = useTransition();
  const [error, setError] = useState<string | null>(null);
  // Reads run on the server after posting or "Update status"; the page refreshes until one lands.
  const reading = readPending || requesting;

  useEffect(() => {
    if (!readPending) return;
    const id = setInterval(() => router.refresh(), POLL_MS);
    return () => clearInterval(id);
  }, [readPending, router]);
  const canRead = sources.length > 0 || tasks.length > 0 || notes.length > 0;

  function update() {
    setError(null);
    startRequesting(async () => {
      const result = await refreshProgressAction(goal.id);
      if (!result.ok) setError(result.error);
    });
  }

  return (
    <>
      <GoalHeader goal={goal} canUpdate={canRead} reading={reading} onUpdate={update} />
      {/* Keyed by week, so a new week starts with an empty field. */}
      <WeekObjective
        key={week.start}
        goalId={goal.id}
        weekStart={week.start}
        saved={week.objective}
        lastWeek={week.lastWeek}
      />
      <ProgressCard read={read} canRead={canRead} reading={reading} error={error ?? readError} onUpdate={update} />
      {/* Tasks, with the read's suggestions underneath as candidates to add. */}
      <TasksSection
        goalId={goal.id}
        tasks={tasks}
        suggestions={read?.suggestions ?? []}
        hasRead={read !== null}
        reading={reading}
        onRefresh={update}
        clock={clock}
        today={today}
      />
      {/* Rendered here rather than passed in from the server page: a server-built element
          that arrives late in a streamed action response trips React's dev-only key check. */}
      <SourcesSection
        goalId={goal.id}
        goal={{ title: goal.title, icon: goal.icon, color: goal.color }}
        sources={sources}
        connections={connections}
      />
      {/* Posting a note starts a read on the server; the page shows it via readPending. */}
      <NotesSection goalId={goal.id} notes={notes} author={author} clock={clock} />
    </>
  );
}
