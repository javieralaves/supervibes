import { Suspense } from "react";

import { Skeleton } from "@/components/skeleton";
import { TimeZoneSync } from "@/components/time-zone-sync";
import { requireUser } from "@/lib/session";
import { getTimeZone } from "@/lib/settings";

import { RailNav, RailNavView } from "./rail-nav";
import { UserMenu } from "./user-menu";

async function RailUser() {
  const user = await requireUser();
  const timeZone = await getTimeZone(user.id);
  return (
    <>
      <UserMenu user={{ name: user.name, email: user.email, image: user.image }} />
      <TimeZoneSync stored={timeZone} />
    </>
  );
}

/** The app's left rail: main sections, and the account menu at the bottom. It sits on the shell, beside the app's window. */
export function AppRail() {
  return (
    <aside data-app-rail className="relative z-30 flex w-16 shrink-0 flex-col items-center py-3">
      <Suspense fallback={<RailNavView pathname={null} />}>
        <RailNav />
      </Suspense>

      <div className="mt-auto flex">
        <Suspense fallback={<Skeleton className="h-10 w-10 rounded-full" />}>
          <RailUser />
        </Suspense>
      </div>
    </aside>
  );
}
