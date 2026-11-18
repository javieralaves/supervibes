import type { Metadata } from "next";
import { Suspense } from "react";

import { Skeleton } from "@/components/skeleton";
import { listRecentCalls } from "@/lib/ai-usage";
import { requireUser } from "@/lib/session";
import { getSettings } from "@/lib/settings";

import { SettingsForm } from "./settings-form";
import { UsageView } from "./usage-view";

export const metadata: Metadata = { title: "Settings · Supervibes" };

async function Form() {
  const user = await requireUser();
  return <SettingsForm initial={await getSettings(user.id)} />;
}

async function Usage() {
  const user = await requireUser();
  return <UsageView calls={await listRecentCalls(user.id)} />;
}

export default function SettingsPage() {
  return (
    <div className="flex flex-1 flex-col">
      <main className="animate-rise mx-auto w-full max-w-3xl flex-1 px-4 pb-16 pt-12 sm:px-8 sm:pt-20">
        <h1 className="text-3xl font-semibold tracking-[-0.03em] text-foreground sm:text-4xl">Settings</h1>
        <p className="mt-3 max-w-lg text-base leading-relaxed text-muted">Make Supervibes fit how your days work.</p>

        <div className="mt-10">
          <Suspense
            fallback={
              <div className="grid gap-3">
                <Skeleton className="h-[220px] rounded-2xl" />
                <Skeleton className="h-[150px] rounded-2xl" />
              </div>
            }
          >
            <Form />
          </Suspense>
        </div>

        <section aria-labelledby="usage-heading" className="mt-14">
          <h2 id="usage-heading" className="text-lg font-semibold tracking-[-0.02em] text-foreground">
            Usage
          </h2>
          <p className="mb-4 mt-1 max-w-lg text-sm leading-relaxed text-muted">
            What Supervibes&rsquo; calls to Claude cost over the last 30 days. Costs are estimates from token counts.
          </p>
          <Suspense fallback={<Skeleton className="h-[320px] rounded-2xl" />}>
            <Usage />
          </Suspense>
        </section>
      </main>
    </div>
  );
}
