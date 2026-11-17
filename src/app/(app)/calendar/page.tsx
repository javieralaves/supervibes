import type { Metadata } from "next";
import { Suspense } from "react";

import { Skeleton } from "@/components/skeleton";
import { listOpenSuggestions } from "@/lib/progress";
import { requireUser } from "@/lib/session";

import { DayCalendar } from "./day-calendar";

export const metadata: Metadata = { title: "Calendar · Supervibes" };

async function Today() {
  const user = await requireUser();
  const groups = await listOpenSuggestions(user.id);
  return <DayCalendar groups={groups} />;
}

export default function CalendarPage() {
  return (
    <div className="flex flex-1 flex-col">
      <main className="animate-rise mx-auto w-full max-w-3xl flex-1 px-4 pb-16 pt-12 sm:px-8 sm:pt-20">
        <h1 className="sr-only">Calendar</h1>

        <div>
          <Suspense
            fallback={
              <div>
                <Skeleton className="mb-3 h-5 w-48" />
                <Skeleton className="h-[calc(100dvh-12rem)] min-h-[420px] rounded-2xl" />
              </div>
            }
          >
            <Today />
          </Suspense>
        </div>
      </main>
    </div>
  );
}
