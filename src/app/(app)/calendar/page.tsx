import type { Metadata } from "next";
import { Suspense } from "react";

import { Skeleton } from "@/components/skeleton";
import { listBlocksAroundNow } from "@/lib/blocks";
import { listGoals } from "@/lib/goals";
import { requireUser } from "@/lib/session";
import { listOpenTasks } from "@/lib/tasks";
import { getSettings } from "@/lib/settings";

import { DayCalendar } from "./day-calendar";

export const metadata: Metadata = { title: "Calendar · Supervibes" };

// Posting a recap starts a progress read that runs after the response, within this limit.
export const maxDuration = 300;

async function Today() {
  const user = await requireUser();
  const [tasks, settings, goals, blocks] = await Promise.all([
    listOpenTasks(user.id),
    getSettings(user.id),
    listGoals(user.id),
    listBlocksAroundNow(user.id),
  ]);
  return (
    <DayCalendar
      tasks={tasks.map(({ id, goalId, title, minutes }) => ({ id, goalId, title, minutes }))}
      settings={settings}
      goals={goals.map(({ id, title, icon, color }) => ({ id, title, icon, color }))}
      blocks={blocks.map((b) => ({
        ...b,
        taskDone: b.taskDone ?? false,
        recapped: b.recapped ?? false,
        startsAt: b.startsAt.toISOString(),
        endsAt: b.endsAt.toISOString(),
      }))}
    />
  );
}

export default function CalendarPage() {
  return (
    <div className="flex flex-1 flex-col">
      {/* The top bar spans the page; the calendar below fills the rest of the viewport's height. */}
      <main className="animate-rise flex h-dvh min-h-[540px] w-full flex-col">
        <h1 className="sr-only">Calendar</h1>

        <Suspense
          fallback={
            <>
              <div className="h-14 shrink-0 bg-background shadow-[inset_0_-1px_0_var(--card-border)]" />
              <div className="mx-auto flex w-full max-w-3xl flex-1 flex-col px-4 py-4 sm:px-8 sm:py-6">
                <Skeleton className="flex-1 rounded-2xl" />
              </div>
            </>
          }
        >
          <Today />
        </Suspense>
      </main>
    </div>
  );
}
