import { Suspense } from "react";

import { Skeleton } from "@/components/skeleton";
import { requireUser } from "@/lib/session";

import { RailNav, RailNavView } from "./rail-nav";
import { UserMenu } from "./user-menu";

async function RailUser() {
  const user = await requireUser();
  return <UserMenu user={{ name: user.name, email: user.email, image: user.image }} />;
}

/** The app's left rail: main sections, and the account menu at the bottom. */
export function AppRail() {
  return (
    <aside className="fixed inset-y-0 left-0 z-30 flex w-16 flex-col items-center bg-background py-3 shadow-[inset_-1px_0_0_var(--card-border)]">
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
