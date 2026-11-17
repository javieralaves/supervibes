import type { Metadata } from "next";
import { Suspense } from "react";

import { Skeleton } from "@/components/skeleton";
import { listOpenSuggestions } from "@/lib/progress";
import { requireUser } from "@/lib/session";
import { getSettings } from "@/lib/settings";

import { DayCalendar } from "./day-calendar";

export const metadata: Metadata = { title: "Calendar · Supervibes" };

async function Today() {
  const user = await requireUser();
  const [groups, settings] = await Promise.all([listOpenSuggestions(user.id), getSettings(user.id)]);
  return <DayCalendar groups={groups} settings={settings} />;
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
