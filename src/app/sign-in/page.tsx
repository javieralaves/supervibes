import type { Metadata } from "next";
import { Suspense } from "react";

import {
  GoogleSignInButton,
  GoogleSignInButtonPlaceholder,
} from "./google-sign-in-button";

export const metadata: Metadata = {
  title: "Sign in · Supervibes",
};

export default function SignInPage() {
  return (
    <main className="flex flex-1 items-center justify-center bg-zinc-50 px-4 py-16 dark:bg-black">
      <div className="w-full max-w-sm rounded-2xl border border-black/[.08] bg-white p-8 shadow-sm dark:border-white/[.12] dark:bg-zinc-950">
        <h1 className="text-2xl font-semibold tracking-tight text-black dark:text-zinc-50">
          Supervibes
        </h1>
        <p className="mt-2 text-sm text-zinc-600 dark:text-zinc-400">
          Sign in to continue.
        </p>
        <div className="mt-8">
          <Suspense fallback={<GoogleSignInButtonPlaceholder />}>
            <GoogleSignInButton />
          </Suspense>
        </div>
      </div>
    </main>
  );
}
