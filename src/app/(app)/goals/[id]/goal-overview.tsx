"use client";

import { useState, useTransition } from "react";

import { refreshProgressAction } from "./actions";
import { GoalHeader } from "./goal-header";
import { NextMoves, type SuggestionView } from "./next-moves";
import { NotesSection, type NoteAuthor, type NoteView } from "./notes-section";
import { ProgressCard, type ReadView } from "./progress-card";

type Props = {
  goal: { id: string; title: string; icon: string; color: string };
  read: (ReadView & { suggestions: SuggestionView[] }) | null;
  notes: NoteView[];
  author: NoteAuthor;
  hasSources: boolean;
  /** Whether the goal has any tasks, which a read can also go on. */
  hasTasks: boolean;
  /** The Tasks section, rendered between the suggestions and the sources. */
  tasks: React.ReactNode;
  /** The Sources section, rendered between the tasks and the notes. */
  sources: React.ReactNode;
};

/** Goal header, progress read, suggestions, tasks, sources and notes, sharing one "reading progress" state. */
export function GoalOverview({ goal, read, notes, author, hasSources, hasTasks, tasks, sources }: Props) {
  const [reading, startReading] = useTransition();
  const [error, setError] = useState<string | null>(null);
  const canRead = hasSources || hasTasks || notes.length > 0;

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
      {read && <NextMoves goalId={goal.id} suggestions={read.suggestions} reading={reading} onDone={update} />}
      {tasks}
      {sources}
      {/* A new note should change the read, so it triggers one straight away. */}
      <NotesSection goalId={goal.id} notes={notes} author={author} onPosted={update} />
    </>
  );
}
