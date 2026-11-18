import { ArrowLeft01Icon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { Suspense } from "react";
import * as z from "zod";

import { Skeleton } from "@/components/skeleton";
import { listConnections } from "@/lib/connections";
import { requireUser } from "@/lib/session";
import { getReadStatus } from "@/lib/background-read";
import { getLatestRead } from "@/lib/progress";
import { listPosts } from "@/lib/posts";
import { getGoal, listSources } from "@/lib/sources";
import { getSettings, getTimeZone } from "@/lib/settings";
import { todayIn } from "@/lib/target-date";
import { listTasks, listTaskSchedules } from "@/lib/tasks";

import { GoalOverview } from "./goal-overview";

export const metadata: Metadata = { title: "Goal · Supervibes" };

// Progress reads run after this page's server actions respond, within this limit.
export const maxDuration = 300;

async function GoalDetail({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  if (!z.uuid().safeParse(id).success) notFound();

  const user = await requireUser();
  const goal = await getGoal(user.id, id);
  if (!goal) notFound();

  const [sources, read, readStatus, connections, posts, tasks, schedules, settings, timeZone] = await Promise.all([
    listSources(user.id, id),
    getLatestRead(user.id, id),
    getReadStatus(user.id, id),
    listConnections(user.id),
    listPosts(user.id, id),
    listTasks(user.id, id),
    listTaskSchedules(user.id, id),
    getSettings(user.id),
    getTimeZone(user.id),
  ]);

  return (
    <GoalOverview
      goal={goal}
      read={read && { ...read, createdAt: read.createdAt.toISOString() }}
      readPending={readStatus.pending}
      readError={readStatus.error}
      notes={posts.map((p) => ({
        id: p.id,
        body: p.body,
        completedSuggestion: p.completedSuggestion,
        completedTask: p.completedTask,
        taskId: p.taskId,
        taskDescription: p.taskDescription ?? null,
        session: p.session,
        breadcrumbs: p.breadcrumbs,
        createdAt: p.createdAt.toISOString(),
        updatedAt: p.updatedAt.toISOString(),
      }))}
      author={{ name: user.name, image: user.image }}
      tasks={tasks.map((t) => ({
        id: t.id,
        title: t.title,
        description: t.description,
        minutes: t.minutes,
        doneAt: t.doneAt?.toISOString() ?? null,
        plannedFor: t.plannedFor,
        dueOn: t.dueOn,
        scheduledAt: schedules.get(t.id)?.toISOString() ?? null,
      }))}
      clock={settings.clock}
      // The person's own today, so the server and their browser agree on "Today" and "Overdue".
      today={todayIn(timeZone)}
      sources={sources}
      connections={connections.filter((c) => c.status === "connected").map((c) => ({ id: c.id, provider: c.provider }))}
    />
  );
}

export default function GoalPage({ params }: PageProps<"/goals/[id]">) {
  return (
    <div className="flex flex-1 flex-col">

      <main className="animate-rise mx-auto w-full max-w-3xl flex-1 px-4 pb-20 pt-8 sm:px-8 sm:pt-14">
        <Link
          href="/"
          className="mb-8 inline-flex items-center gap-1.5 text-sm font-medium text-muted transition-colors hover:text-foreground"
        >
          <HugeiconsIcon icon={ArrowLeft01Icon} size={16} />
          All goals
        </Link>
        <Suspense
          fallback={
            <div className="space-y-6">
              <div className="flex items-center gap-5">
                <Skeleton className="h-16 w-16 rounded-[20px]" />
                <Skeleton className="h-9 w-72" />
              </div>
              <Skeleton className="h-40 rounded-2xl" />
            </div>
          }
        >
          <GoalDetail params={params} />
        </Suspense>
      </main>
    </div>
  );
}
