import type { Metadata } from "next";
import { Suspense } from "react";

import { Skeleton } from "@/components/skeleton";
import { listOpenSuggestions } from "@/lib/progress";
import { listBlocksAroundNow } from "@/lib/blocks";
import { listGoals } from "@/lib/goals";
import { requireUser } from "@/lib/session";
import { listOpenTasks } from "@/lib/tasks";
import { getSettings } from "@/lib/settings";

import { DayCalendar } from "./day-calendar";

export const metadata: Metadata = { title: "Calendar · Supervibes" };

async function Today() {
  const user = await requireUser();
  const [groups, tasks, settings, goals, blocks] = await Promise.all([
    listOpenSuggestions(user.id),
    listOpenTasks(user.id),
    getSettings(user.id),
    listGoals(user.id),
    listBlocksAroundNow(user.id),
  ]);
  return (
    <DayCalendar
      groups={groups}
      tasks={tasks.map(({ id, goalId, title, minutes }) => ({ id, goalId, title, minutes }))}
      settings={settings}
      goals={goals.map(({ id, title, icon, color }) => ({ id, title, icon, color }))}
      blocks={blocks.map((b) => ({
        ...b,
        taskDone: b.taskDone ?? false,
        startsAt: b.startsAt.toISOString(),
        endsAt: b.endsAt.toISOString(),
      }))}
    />
  );
}

export default function CalendarPage() {
  return (
    <div className="flex flex-1 flex-col">
      {/* The calendar fills the viewport's height, keeping a gap above and below. */}
      <main className="animate-rise mx-auto flex h-dvh min-h-[540px] w-full max-w-3xl flex-col px-4 py-4 sm:px-8 sm:py-8">
        <h1 className="sr-only">Calendar</h1>

        <Suspense fallback={<Skeleton className="flex-1 rounded-2xl" />}>
          <Today />
        </Suspense>
      </main>
    </div>
  );
}
