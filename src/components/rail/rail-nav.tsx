"use client";

import { Calendar03Icon, Plug01Icon, Target02Icon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import Link from "next/link";
import { usePathname } from "next/navigation";

const ITEMS = [
  { href: "/", label: "Goals", icon: Target02Icon, match: (p: string) => p === "/" || p.startsWith("/goals") },
  { href: "/calendar", label: "Calendar", icon: Calendar03Icon, match: (p: string) => p.startsWith("/calendar") },
  { href: "/connections", label: "Connections", icon: Plug01Icon, match: (p: string) => p.startsWith("/connections") },
];

export function RailNav() {
  return <RailNavView pathname={usePathname()} />;
}

/** Same items with no active state; the Suspense fallback while the path streams in. */
export function RailNavView({ pathname }: { pathname: string | null }) {
  return (
    <nav aria-label="Main" className="flex flex-col items-center gap-1.5">
      {ITEMS.map((item) => {
        const active = pathname !== null && item.match(pathname);
        return (
          <Link
            key={item.href}
            href={item.href}
            aria-label={item.label}
            aria-current={active ? "page" : undefined}
            className={`group relative flex h-10 w-10 items-center justify-center rounded-xl transition-colors focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-foreground/30 ${
              active ? "bg-foreground/[.08] text-foreground" : "text-muted hover:bg-wash hover:text-foreground"
            }`}
          >
            <HugeiconsIcon icon={item.icon} size={20} strokeWidth={1.8} />
            <RailTooltip>{item.label}</RailTooltip>
          </Link>
        );
      })}
    </nav>
  );
}

/** Label that appears to the right of a rail item on hover or keyboard focus. */
export function RailTooltip({ children }: { children: React.ReactNode }) {
  return (
    <span
      aria-hidden="true"
      className="pointer-events-none absolute left-full top-1/2 z-50 ml-3 -translate-y-1/2 whitespace-nowrap rounded-lg bg-foreground px-2.5 py-1 text-xs font-medium text-background opacity-0 shadow-sm transition-opacity group-hover:opacity-100 group-focus-visible:opacity-100 [@media(hover:none)]:hidden"
    >
      {children}
    </span>
  );
}
