import type { Metadata } from "next";
import { Suspense } from "react";

import { ProviderMark } from "@/components/provider-mark";
import { Skeleton } from "@/components/skeleton";
import { listConnections } from "@/lib/connections";
import { isProviderConfigured } from "@/lib/mcp-oauth";
import { PROVIDERS, PROVIDER_KEYS } from "@/lib/providers";
import { requireUser } from "@/lib/session";

import { ConnectionMenu } from "./connection-menu";
import { StatusBanner } from "./status-banner";

export const metadata: Metadata = { title: "Connections · Supervibes" };

const dateFormat = new Intl.DateTimeFormat("en", { month: "short", day: "numeric", year: "numeric" });

async function ConnectionList() {
  const user = await requireUser();
  const connected = new Map((await listConnections(user.id)).map((c) => [c.provider, c]));

  return (
    <ul className="grid gap-3">
      {PROVIDER_KEYS.map((key) => {
        const provider = PROVIDERS[key];
        const connection = connected.get(key);
        const configured = isProviderConfigured(key);

        return (
          <li
            key={key}
            className="flex flex-col gap-4 rounded-2xl border border-card-border bg-card p-5 sm:flex-row sm:items-center"
          >
            <div className="flex min-w-0 flex-1 items-center gap-4">
              <ProviderMark provider={key} />
              <div className="min-w-0">
                <p className="font-semibold tracking-[-0.01em] text-foreground">{provider.label}</p>
                <p className="text-sm text-muted">
                  {connection
                    ? connection.status === "error"
                      ? `Needs attention: ${connection.lastError ?? "reconnect it."}`
                      : `Connected ${dateFormat.format(connection.createdAt)}`
                    : provider.description}
                </p>
              </div>
            </div>

            <div className="flex shrink-0 items-center gap-2">
              {connection ? (
                <ConnectionMenu provider={key} label={provider.label} />
              ) : configured ? (
                <a
                  href={`/api/connections/${key}/start`}
                  className="inline-flex h-10 items-center rounded-xl bg-foreground px-4 text-sm font-semibold text-background transition-opacity hover:opacity-90"
                >
                  Connect
                </a>
              ) : (
                <span className="text-sm text-muted">Needs one-time setup</span>
              )}
            </div>
          </li>
        );
      })}
    </ul>
  );
}

export default function ConnectionsPage() {
  return (
    <div className="flex flex-1 flex-col">

      <main className="animate-rise mx-auto w-full max-w-3xl flex-1 px-4 pb-16 pt-12 sm:px-8 sm:pt-20">
        <h1 className="text-3xl font-semibold tracking-[-0.03em] text-foreground sm:text-4xl">Connections</h1>
        <p className="mt-3 max-w-lg text-base leading-relaxed text-muted">
          Let Supervibes read activity from the apps where your work happens. Access is read-only, and
          you decide per goal what counts.
        </p>

        <div className="mt-10">
          <Suspense>
            <StatusBanner />
          </Suspense>
          <Suspense
            fallback={
              <div className="grid gap-3">
                <Skeleton className="h-[84px] rounded-2xl" />
                <Skeleton className="h-[84px] rounded-2xl" />
                <Skeleton className="h-[84px] rounded-2xl" />
              </div>
            }
          >
            <ConnectionList />
          </Suspense>
        </div>
      </main>
    </div>
  );
}
