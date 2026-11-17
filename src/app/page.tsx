import { headers } from "next/headers";
import { redirect } from "next/navigation";
import { Suspense } from "react";

import { Backdrop } from "@/components/backdrop";
import { Wordmark } from "@/components/logo";
import { auth } from "@/lib/auth";
import { listGoals } from "@/lib/goals";
import { requireUser } from "@/lib/session";

import { GoalsBoard } from "./goals/goals-board";

async function signOut() {
  "use server";
  await auth.api.signOut({ headers: await headers() });
  redirect("/sign-in");
}

function Avatar({ name, image }: { name: string; image: string | null | undefined }) {
  return image ? (
    // eslint-disable-next-line @next/next/no-img-element
    <img
      src={image}
      alt=""
      referrerPolicy="no-referrer"
      className="h-9 w-9 rounded-full ring-2 ring-white/80 dark:ring-white/10"
    />
  ) : (
    <span className="flex h-9 w-9 items-center justify-center rounded-full bg-linear-to-br from-glow-1 to-glow-2 text-sm font-semibold text-white">
      {name.charAt(0)}
    </span>
  );
}

async function UserMenu() {
  const user = await requireUser();

  return (
    <div className="flex items-center gap-3">
      <div className="hidden text-right sm:block">
        <p className="text-sm font-semibold leading-tight text-foreground">{user.name}</p>
        <p className="text-xs leading-tight text-muted">{user.email}</p>
      </div>
      <Avatar name={user.name} image={user.image} />
      <form action={signOut}>
        <button
          type="submit"
          className="h-9 rounded-xl border border-card-border bg-card px-3.5 text-sm font-medium text-foreground backdrop-blur-xl transition-colors hover:bg-white/90 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-glow-2 dark:hover:bg-white/10"
        >
          Sign out
        </button>
      </form>
    </div>
  );
}

async function Greeting() {
  const user = await requireUser();
  const firstName = user.name.split(" ")[0] || user.name;

  return (
    <h1 className="text-4xl font-semibold leading-[1.05] tracking-[-0.035em] text-foreground sm:text-5xl">
      Hey {firstName},
      <br />
      <span className="bg-linear-to-r from-ink-1 via-ink-2 to-ink-3 bg-clip-text text-transparent">
        good to see you.
      </span>
    </h1>
  );
}

async function Goals() {
  const user = await requireUser();
  const goals = await listGoals(user.id);
  return <GoalsBoard goals={goals} />;
}

function Skeleton({ className }: { className: string }) {
  return <div aria-hidden="true" className={`animate-pulse rounded-xl bg-foreground/[.07] ${className}`} />;
}

export default function Home() {
  return (
    <div className="flex flex-1 flex-col">
      <Backdrop intensity="soft" />

      <header className="mx-auto flex w-full max-w-5xl items-center justify-between px-4 py-5 sm:px-6">
        <Wordmark />
        <Suspense
          fallback={
            <div className="flex items-center gap-3">
              <Skeleton className="h-9 w-9 rounded-full" />
              <Skeleton className="h-9 w-20" />
            </div>
          }
        >
          <UserMenu />
        </Suspense>
      </header>

      <main className="animate-rise mx-auto w-full max-w-5xl flex-1 px-4 pb-16 pt-10 sm:px-6 sm:pt-16">
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
                <Skeleton className="h-[84px] rounded-3xl" />
                <Skeleton className="h-[84px] rounded-3xl" />
                <Skeleton className="h-[84px] rounded-3xl" />
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
