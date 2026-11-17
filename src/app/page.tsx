import { headers } from "next/headers";
import { redirect } from "next/navigation";
import { Suspense } from "react";

import { auth } from "@/lib/auth";
import { requireUser } from "@/lib/session";

async function signOut() {
  "use server";
  await auth.api.signOut({ headers: await headers() });
  redirect("/sign-in");
}

async function Account() {
  const user = await requireUser();

  return (
    <div className="flex flex-col gap-6 sm:flex-row sm:items-center sm:justify-between">
      <div className="flex items-center gap-4">
        {user.image ? (
          // eslint-disable-next-line @next/next/no-img-element
          <img
            src={user.image}
            alt=""
            referrerPolicy="no-referrer"
            className="h-12 w-12 rounded-full"
          />
        ) : (
          <div className="flex h-12 w-12 items-center justify-center rounded-full bg-zinc-200 text-lg font-medium dark:bg-zinc-800">
            {user.name.charAt(0)}
          </div>
        )}
        <div>
          <p className="font-medium text-black dark:text-zinc-50">{user.name}</p>
          <p className="text-sm text-zinc-600 dark:text-zinc-400">{user.email}</p>
        </div>
      </div>
      <form action={signOut}>
        <button
          type="submit"
          className="h-10 rounded-full border border-black/[.12] px-5 text-sm font-medium transition-colors hover:bg-zinc-50 dark:border-white/[.16] dark:hover:bg-zinc-900"
        >
          Sign out
        </button>
      </form>
    </div>
  );
}

function AccountSkeleton() {
  return (
    <div className="flex items-center gap-4" aria-hidden="true">
      <div className="h-12 w-12 animate-pulse rounded-full bg-zinc-200 dark:bg-zinc-800" />
      <div className="flex flex-col gap-2">
        <div className="h-4 w-32 animate-pulse rounded bg-zinc-200 dark:bg-zinc-800" />
        <div className="h-3 w-44 animate-pulse rounded bg-zinc-200 dark:bg-zinc-800" />
      </div>
    </div>
  );
}

export default function Home() {
  return (
    <main className="flex flex-1 justify-center bg-zinc-50 px-4 py-16 dark:bg-black">
      <div className="w-full max-w-2xl">
        <h1 className="text-3xl font-semibold tracking-tight text-black dark:text-zinc-50">
          Supervibes
        </h1>
        <section className="mt-8 rounded-2xl border border-black/[.08] bg-white p-6 dark:border-white/[.12] dark:bg-zinc-950">
          <Suspense fallback={<AccountSkeleton />}>
            <Account />
          </Suspense>
        </section>
      </div>
    </main>
  );
}
