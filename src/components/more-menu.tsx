"use client";

import { MoreHorizontalIcon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon, type IconSvgElement } from "@hugeicons/react";
import * as DropdownMenu from "@radix-ui/react-dropdown-menu";

import { roundButtonClass } from "@/components/round-button";

/** Circular "more options" button with a dropdown of actions. */
export function MoreMenu({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <DropdownMenu.Root>
      <DropdownMenu.Trigger
        aria-label={label}
        className={roundButtonClass}
      >
        <HugeiconsIcon icon={MoreHorizontalIcon} size={18} />
      </DropdownMenu.Trigger>
      <DropdownMenu.Portal>
        <DropdownMenu.Content
          align="end"
          sideOffset={6}
          collisionPadding={12}
          className="z-50 w-48 rounded-xl border border-card-border bg-card p-1.5 shadow-[0_12px_32px_-12px_rgb(0_0_0/0.25)] outline-none data-[state=open]:animate-[pop-in_140ms_ease-out]"
        >
          {children}
        </DropdownMenu.Content>
      </DropdownMenu.Portal>
    </DropdownMenu.Root>
  );
}

type ItemProps = {
  icon: IconSvgElement;
  children: React.ReactNode;
  destructive?: boolean;
  disabled?: boolean;
  onSelect?: () => void;
  /** Render as a link instead of a button. */
  href?: string;
};

export function MoreMenuItem({ icon, children, destructive, disabled, onSelect, href }: ItemProps) {
  const className = `flex h-9 cursor-default select-none items-center gap-2.5 rounded-lg px-2.5 text-sm font-medium outline-none data-[disabled]:opacity-50 data-[highlighted]:bg-wash ${
    destructive ? "text-red-600 dark:text-red-400" : "text-foreground"
  }`;
  const iconEl = <HugeiconsIcon icon={icon} size={16} className={destructive ? undefined : "text-muted"} />;

  if (href) {
    return (
      <DropdownMenu.Item asChild disabled={disabled} className={className}>
        <a href={href}>
          {iconEl}
          {children}
        </a>
      </DropdownMenu.Item>
    );
  }
  return (
    <DropdownMenu.Item disabled={disabled} onSelect={onSelect} className={className}>
      {iconEl}
      {children}
    </DropdownMenu.Item>
  );
}
