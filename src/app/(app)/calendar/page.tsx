import type { Metadata } from "next";
import { Suspense } from "react";

import { Skeleton } from "@/components/skeleton";
import { CALENDAR_DAYS_AHEAD, CALENDAR_DAYS_BACK, listBlocksAroundNow } from "@/lib/blocks";
import { listGoals } from "@/lib/goals";
import { requireUser } from "@/lib/session";
import { draftRecapsAfterResponse, listAutoRecapCandidates } from "@/lib/recap";
import { listOpenTasks } from "@/lib/tasks";
import { getSettings, getTimeZone } from "@/lib/settings";
import { addDays, todayIn, weekStartOf } from "@/lib/target-date";
import { listObjectivesBetween } from "@/lib/week-objectives";

import { DayCalendar } from "./day-calendar";

export const metadata: Metadata = { title: "Calendar · Supervibes" };

// Posting a recap starts a progress read, and ended sessions draft their recaps,
// after the response, within this limit.
export const maxDuration = 300;

/** Sessions drafted per visit; any more wait for the next visit. */
const AUTO_RECAPS_PER_VISIT = 3;

async function Today() {
  const user = await requireUser();
  const timeZone = await getTimeZone(user.id);
  const today = todayIn(timeZone);
  const [tasks, settings, goals, blocks, toRecap, objectives] = await Promise.all([
    listOpenTasks(user.id),
    getSettings(user.id),
    listGoals(user.id),
    listBlocksAroundNow(user.id),
    listAutoRecapCandidates(user.id, AUTO_RECAPS_PER_VISIT),
    // Every goal's weekly objectives across the weeks the calendar can show.
    listObjectivesBetween(
      user.id,
      weekStartOf(addDays(today, -CALENDAR_DAYS_BACK)),
      weekStartOf(addDays(today, CALENDAR_DAYS_AHEAD)),
    ),
  ]);
  // Sessions that just ended draft their recaps once the page is sent; the calendar refreshes to pick them up.
  const drafting = new Set(toRecap);
  draftRecapsAfterResponse(user.id, toRecap);
  return (
    <DayCalendar
      tasks={tasks.map(({ id, goalId, title, minutes, plannedFor, dueOn }) => ({ id, goalId, title, minutes, plannedFor, dueOn }))}
      settings={settings}
      objectives={objectives}
      goals={goals.map(({ id, title, icon, color }) => ({ id, title, icon, color }))}
      blocks={blocks.map((b) => ({
        ...b,
        taskDone: b.taskDone ?? false,
        recapPost: b.recapPost ?? null,
        recapDrafting: drafting.has(b.id) || (b.recapDrafting ?? false),
        startsAt: b.startsAt.toISOString(),
        endsAt: b.endsAt.toISOString(),
      }))}
    />
  );
}

export default function CalendarPage() {
  return (
    // min-h-0: held to the app window's height, so the calendar scrolls inside itself, not the window.
    <div className="flex min-h-0 flex-1 flex-col">
      {/* The top bar spans the window; the calendar below fills the rest of its height. */}
      <main className="animate-rise flex min-h-[540px] w-full flex-1 flex-col">
        <h1 className="sr-only">Calendar</h1>

        <Suspense
          fallback={
            <>
              <div className="h-14 shrink-0 bg-background shadow-[inset_0_-1px_0_var(--card-border)]" />
              <div className="mx-auto flex w-full max-w-3xl flex-1 flex-col p-4">
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
