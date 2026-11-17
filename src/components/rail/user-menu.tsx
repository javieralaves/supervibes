"use client";

import { Logout01Icon, Settings02Icon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import * as DropdownMenu from "@radix-ui/react-dropdown-menu";
import Link from "next/link";
import { useTransition } from "react";

import { Avatar } from "@/components/avatar";
import { signOutAction } from "@/lib/auth-actions";

const itemClass =
  "flex h-9 cursor-default select-none items-center gap-2.5 rounded-lg px-2.5 text-sm font-medium text-foreground outline-none data-[disabled]:opacity-50 data-[highlighted]:bg-wash";

type User = { name: string; email: string; image: string | null | undefined };

export function UserMenu({ user }: { user: User }) {
  const [signingOut, startSignOut] = useTransition();

  return (
    <DropdownMenu.Root>
      <DropdownMenu.Trigger
        aria-label={`Account: ${user.name}`}
        className="rounded-full transition-opacity hover:opacity-85 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-foreground/30 data-[state=open]:ring-2 data-[state=open]:ring-foreground/20"
      >
        <Avatar name={user.name} image={user.image} />
      </DropdownMenu.Trigger>

      <DropdownMenu.Portal>
        <DropdownMenu.Content
          side="right"
          align="end"
          sideOffset={12}
          collisionPadding={12}
          className="z-50 w-64 rounded-xl border border-card-border bg-card p-1.5 shadow-[0_12px_32px_-12px_rgb(0_0_0/0.25)] outline-none data-[state=open]:animate-[pop-in_140ms_ease-out]"
        >
          <DropdownMenu.Label className="flex items-center gap-3 px-2.5 py-2">
            <Avatar name={user.name} image={user.image} />
            <span className="min-w-0">
              <span className="block truncate text-sm font-semibold text-foreground">{user.name}</span>
              <span className="block truncate text-xs text-muted">{user.email}</span>
            </span>
          </DropdownMenu.Label>

          <DropdownMenu.Separator className="my-1.5 h-px bg-card-border" />

          <DropdownMenu.Item asChild className={itemClass}>
            <Link href="/settings">
              <HugeiconsIcon icon={Settings02Icon} size={16} className="text-muted" />
              Settings
            </Link>
          </DropdownMenu.Item>

          <DropdownMenu.Item
            disabled={signingOut}
            onSelect={(event) => {
              event.preventDefault();
              startSignOut(() => signOutAction());
            }}
            className={itemClass}
          >
            <HugeiconsIcon icon={Logout01Icon} size={16} className="text-muted" />
            {signingOut ? "Signing out…" : "Sign out"}
          </DropdownMenu.Item>
        </DropdownMenu.Content>
      </DropdownMenu.Portal>
    </DropdownMenu.Root>
  );
}
