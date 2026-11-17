"use client";

import { useState, useTransition } from "react";

import { refreshProgressAction } from "./actions";
import { GoalHeader } from "./goal-header";
import { NotesSection, type NoteAuthor, type NoteView } from "./notes-section";
import { ProgressCard, type ReadView } from "./progress-card";

type Props = {
  goal: { id: string; title: string; icon: string; color: string };
  read: ReadView | null;
  notes: NoteView[];
  author: NoteAuthor;
  hasSources: boolean;
  /** The Sources section, rendered between the progress read and the notes. */
  sources: React.ReactNode;
};

/** Goal header, progress read, sources and notes, sharing one "reading progress" state. */
export function GoalOverview({ goal, read, notes, author, hasSources, sources }: Props) {
  const [reading, startReading] = useTransition();
  const [error, setError] = useState<string | null>(null);
  const canRead = hasSources || notes.length > 0;

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
      {sources}
      {/* A new note should change the read, so it triggers one straight away. */}
      <NotesSection goalId={goal.id} notes={notes} author={author} onPosted={update} />
    </>
  );
}
