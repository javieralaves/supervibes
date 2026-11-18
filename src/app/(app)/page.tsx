import { Suspense } from "react";

import { Skeleton } from "@/components/skeleton";
import { listTrajectories } from "@/lib/goal-statuses";
import { listGoals } from "@/lib/goals";
import { getTimeZone } from "@/lib/settings";
import { todayIn } from "@/lib/target-date";
import { requireUser } from "@/lib/session";

import { GoalsBoard } from "./goals/goals-board";

async function Greeting() {
  const user = await requireUser();
  const firstName = user.name.split(" ")[0] || user.name;

  return (
    <h1 className="text-4xl font-semibold leading-[1.05] tracking-[-0.035em] text-foreground sm:text-5xl">
      Hey {firstName},
      <br />
      <span className="text-muted">
        good to see you.
      </span>
    </h1>
  );
}

async function Goals() {
  const user = await requireUser();
  const [goals, timeZone] = await Promise.all([listGoals(user.id), getTimeZone(user.id)]);
  const trajectories = await listTrajectories(
    user.id,
    goals.map((g) => g.id),
    timeZone,
  );
  return <GoalsBoard goals={goals} trajectories={Object.fromEntries(trajectories)} today={todayIn(timeZone)} />;
}

export default function Home() {
  return (
    <div className="flex flex-1 flex-col">

      <main className="animate-rise mx-auto w-full max-w-5xl flex-1 px-4 pb-16 pt-12 sm:px-8 sm:pt-20">
        <Suspense
          fallback={
            <div className="space-y-3">
              <Skeleton className="h-11 w-64" />
              <Skeleton className="h-11 w-80" />
            </div>
          }
        >
          <Greeting />
        </Suspense>

        <p className="mt-5 max-w-md text-base leading-relaxed text-muted">
          Here&apos;s what you&apos;re working toward.
        </p>

        <div className="mt-12">
          <Suspense
            fallback={
              <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
                <Skeleton className="h-[84px] rounded-2xl" />
                <Skeleton className="h-[84px] rounded-2xl" />
                <Skeleton className="h-[84px] rounded-2xl" />
              </div>
            }
          >
            <Goals />
          </Suspense>
        </div>
      </main>
    </div>
  );
}
