import type { Metadata } from "next";
import { Suspense } from "react";

import { Backdrop } from "@/components/backdrop";
import { Wordmark } from "@/components/logo";

import {
  GoogleSignInButton,
  GoogleSignInButtonPlaceholder,
} from "./google-sign-in-button";

export const metadata: Metadata = {
  title: "Sign in · Supervibes",
};

export default function SignInPage() {
  return (
    <main className="flex flex-1 flex-col items-center justify-center px-4 py-16">
      <Backdrop />

      <div className="animate-rise w-full max-w-[400px]">
        <div className="mb-8 flex justify-center">
          <Wordmark size="lg" />
        </div>

        <div className="rounded-[28px] border border-card-border bg-card p-8 shadow-[0_1px_0_0_var(--ring)_inset,0_24px_60px_-20px_rgb(22_20_31/0.25)] backdrop-blur-2xl sm:p-10">
          <h1 className="text-[1.65rem] font-semibold leading-tight tracking-[-0.025em] text-foreground">
            Welcome back
          </h1>
          <p className="mt-2 text-[0.95rem] leading-relaxed text-muted">
            Sign in to pick up where you left off.
          </p>

          <div className="mt-8">
            <Suspense fallback={<GoogleSignInButtonPlaceholder />}>
              <GoogleSignInButton />
            </Suspense>
          </div>

          <div className="mt-8 flex items-center gap-2 border-t border-card-border pt-6 text-xs text-muted">
            <svg viewBox="0 0 16 16" className="h-3.5 w-3.5 shrink-0" aria-hidden="true">
              <path
                fill="currentColor"
                d="M8 1a3.5 3.5 0 0 0-3.5 3.5V6H4a1.5 1.5 0 0 0-1.5 1.5v6A1.5 1.5 0 0 0 4 15h8a1.5 1.5 0 0 0 1.5-1.5v-6A1.5 1.5 0 0 0 12 6h-.5V4.5A3.5 3.5 0 0 0 8 1Zm2 5V4.5a2 2 0 1 0-4 0V6h4Z"
              />
            </svg>
            Private space. Access is by invitation.
          </div>
        </div>
      </div>
    </main>
  );
}
