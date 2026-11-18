"use client";

import { useState, useTransition } from "react";

import type { Clock } from "@/lib/settings-schema";

import { refreshProgressAction } from "./actions";
import { GoalHeader } from "./goal-header";
import { NotesSection, type NoteAuthor, type NoteView } from "./notes-section";
import { ProgressCard, type ReadView } from "./progress-card";
import type { ConnectionOption } from "./source-dialog";
import { SourcesSection, type SourceView } from "./sources-section";
import { TasksSection, type SuggestionView, type TaskView } from "./tasks-section";

type Props = {
  goal: { id: string; title: string; description: string | null; targetDate: string | null; icon: string; color: string };
  read: (ReadView & { suggestions: SuggestionView[] }) | null;
  notes: NoteView[];
  author: NoteAuthor;
  tasks: TaskView[];
  /** The user's clock choice, for times like when a task is scheduled. */
  clock: Clock | null;
  sources: SourceView[];
  /** Connected apps a new source can read from. */
  connections: ConnectionOption[];
};

/** Goal header, progress read, tasks and suggestions, sources and activity, sharing one "reading progress" state. */
export function GoalOverview({ goal, read, notes, author, tasks, clock, sources, connections }: Props) {
  const [reading, startReading] = useTransition();
  const [error, setError] = useState<string | null>(null);
  const canRead = sources.length > 0 || tasks.length > 0 || notes.length > 0;

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
      {/* Rendered here rather than passed in from the server page: a server-built element
          that arrives late in a streamed action response trips React's dev-only key check. */}
      <SourcesSection
        goalId={goal.id}
        goal={{ title: goal.title, icon: goal.icon, color: goal.color }}
        sources={sources}
        connections={connections}
      />
      {/* A new note should change the read, so it triggers one straight away. */}
      <NotesSection goalId={goal.id} notes={notes} author={author} clock={clock} onPosted={update} />
    </>
  );
}
