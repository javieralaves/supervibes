"use client";

import { useSearchParams } from "next/navigation";

import { PROVIDERS, isProvider } from "@/lib/providers";

const ERRORS: Record<string, string> = {
  denied: "You cancelled the connection. Nothing was changed.",
  expired: "That sign-in took too long or came from another session. Try connecting again.",
  failed: "The app didn't finish connecting. Try again in a moment.",
  start_failed: "Couldn't reach that app's sign-in. Try again in a moment.",
  not_configured: "This app needs a one-time setup before it can connect.",
  unknown_app: "That app isn't supported yet.",
};

export function StatusBanner() {
  const params = useSearchParams();
  const connected = params.get("connected");
  const error = params.get("error");

  if (connected && isProvider(connected)) {
    return (
      <p role="status" className="mb-6 rounded-xl border border-card-border bg-card px-4 py-3 text-sm text-foreground">
        {PROVIDERS[connected].label} is connected. Add it as a source on any goal.
      </p>
    );
  }
  if (error) {
    return (
      <p role="alert" className="mb-6 rounded-xl border border-red-500/20 bg-red-500/[.07] px-4 py-3 text-sm text-red-700 dark:text-red-300">
        {ERRORS[error] ?? ERRORS.failed}
      </p>
    );
  }
  return null;
}
