"use client";

import { useState, useTransition } from "react";

import type { Clock } from "@/lib/settings-schema";

import { refreshProgressAction } from "./actions";
import { GoalHeader } from "./goal-header";
import { NotesSection, type NoteAuthor, type NoteView } from "./notes-section";
import { ProgressCard, type ReadView } from "./progress-card";
import { TasksSection, type SuggestionView, type TaskView } from "./tasks-section";

type Props = {
  goal: { id: string; title: string; icon: string; color: string };
  read: (ReadView & { suggestions: SuggestionView[] }) | null;
  notes: NoteView[];
  author: NoteAuthor;
  hasSources: boolean;
  tasks: TaskView[];
  /** The user's clock choice, for times like when a task is scheduled. */
  clock: Clock | null;
  /** The Sources section, rendered between the tasks and the notes. */
  sources: React.ReactNode;
};

/** Goal header, progress read, tasks and suggestions, sources and activity, sharing one "reading progress" state. */
export function GoalOverview({ goal, read, notes, author, hasSources, tasks, clock, sources }: Props) {
  const [reading, startReading] = useTransition();
  const [error, setError] = useState<string | null>(null);
  const canRead = hasSources || tasks.length > 0 || notes.length > 0;

  function update() {
    setError(null);
    startReading(async () => {
      const result = await refreshProgressAction(goal.id);
      if (!result.ok) setError(result.error);
    });
  }

  return (
    <>
      <GoalHeader goal={goal} canUpdate={canRead} reading={reading} onUpdate={update} />
      <ProgressCard read={read} canRead={canRead} reading={reading} error={error} onUpdate={update} />
      {/* Tasks, with the read's suggestions underneath as candidates to add. */}
      <TasksSection
        goalId={goal.id}
        tasks={tasks}
        suggestions={read?.suggestions ?? []}
        hasRead={read !== null}
        reading={reading}
        onRefresh={update}
        clock={clock}
      />
      {sources}
      {/* A new note should change the read, so it triggers one straight away. */}
      <NotesSection goalId={goal.id} notes={notes} author={author} onPosted={update} />
    </>
  );
}
