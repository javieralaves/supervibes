"use client";

import { useEffect } from "react";

import { syncTimeZoneAction } from "@/app/(app)/settings/actions";

/**
 * Tells the server the browser's time zone when it differs from the one stored,
 * so "today" on the server (due dates, planned days, prompts) is the person's
 * own day. Renders nothing; on every page, via the rail.
 */
export function TimeZoneSync({ stored }: { stored: string | null }) {
  useEffect(() => {
    let zone: string | undefined;
    try {
      zone = Intl.DateTimeFormat().resolvedOptions().timeZone;
    } catch {
      return;
    }
    if (zone && zone !== stored) void syncTimeZoneAction(zone);
  }, [stored]);
  return null;
}
