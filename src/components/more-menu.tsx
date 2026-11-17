"use client";

import { MoreHorizontalIcon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon, type IconSvgElement } from "@hugeicons/react";
import * as DropdownMenu from "@radix-ui/react-dropdown-menu";

import { roundButtonClass } from "@/components/round-button";

/** Circular "more options" button with a dropdown of actions. */
const smallTriggerClass =
  "flex h-6 w-6 shrink-0 items-center justify-center rounded-full border border-card-border bg-card text-foreground/70 shadow-[0_1px_2px_rgb(15_17_20/0.08)] transition-colors hover:border-line-strong hover:text-foreground focus-visible:outline-2 focus-visible:outline-offset-1 focus-visible:outline-foreground/30 data-[state=open]:border-line-strong data-[state=open]:text-foreground";

export function MoreMenu({
  label,
  children,
  small = false,
}: {
  label: string;
  children: React.ReactNode;
  /** A compact trigger for tight spots, like calendar blocks. */
  small?: boolean;
}) {
  return (
    <DropdownMenu.Root>
      <DropdownMenu.Trigger
        aria-label={label}
        className={small ? smallTriggerClass : roundButtonClass}
      >
        <HugeiconsIcon icon={MoreHorizontalIcon} size={small ? 14 : 18} />
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
