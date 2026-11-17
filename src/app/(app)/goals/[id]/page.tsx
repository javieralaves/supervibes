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
import { getLatestRead } from "@/lib/progress";
import { listPosts } from "@/lib/posts";
import { getGoal, listSources } from "@/lib/sources";

import { GoalOverview } from "./goal-overview";
import { SourcesSection } from "./sources-section";

export const metadata: Metadata = { title: "Goal · Supervibes" };

// Progress reads run inside a server action on this page and can take a while.
export const maxDuration = 300;

async function GoalDetail({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  if (!z.uuid().safeParse(id).success) notFound();

  const user = await requireUser();
  const goal = await getGoal(user.id, id);
  if (!goal) notFound();

  const [sources, read, connections, posts] = await Promise.all([
    listSources(user.id, id),
    getLatestRead(user.id, id),
    listConnections(user.id),
    listPosts(user.id, id),
  ]);

  return (
    <GoalOverview
      goal={goal}
      hasSources={sources.length > 0}
      read={read && { ...read, createdAt: read.createdAt.toISOString() }}
      notes={posts.map((p) => ({
        id: p.id,
        body: p.body,
        completedSuggestion: p.completedSuggestion,
        createdAt: p.createdAt.toISOString(),
        updatedAt: p.updatedAt.toISOString(),
      }))}
      author={{ name: user.name, image: user.image }}
      sources={
        <SourcesSection
          goalId={goal.id}
          goal={{ title: goal.title, icon: goal.icon, color: goal.color }}
          sources={sources}
          connections={connections.filter((c) => c.status === "connected").map((c) => ({ id: c.id, provider: c.provider }))}
        />
      }
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
