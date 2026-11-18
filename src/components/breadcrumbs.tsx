import { Cancel01Icon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";

import { ProviderMark } from "@/components/provider-mark";
import { PROVIDERS } from "@/lib/providers";
import type { Breadcrumb } from "@/lib/recap-schema";

/**
 * Specific things in connected apps a recap drew on: one line each, opening in
 * a new tab. With `onRemove`, each can be taken out (while drafting).
 */
export function Breadcrumbs({
  items,
  onRemove,
  className = "",
}: {
  items: Breadcrumb[];
  onRemove?: (url: string) => void;
  className?: string;
}) {
  if (items.length === 0) return null;
  return (
    <ul className={`-mx-2 ${className}`}>
      {items.map((item) => (
        <li key={item.url} className="group flex items-center gap-1 rounded-lg">
          <a
            href={item.url}
            target="_blank"
            rel="noopener noreferrer"
            title={`Open in ${PROVIDERS[item.provider].label}`}
            className="flex min-w-0 flex-1 items-center gap-2 rounded-lg px-2 py-1.5 text-[13px] leading-snug text-foreground/85 transition-colors hover:bg-wash hover:text-foreground focus-visible:outline-2 focus-visible:outline-foreground/30"
          >
            <ProviderMark provider={item.provider} size="xs" />
            <span className="min-w-0 flex-1 truncate">{item.title}</span>
            <span className="sr-only"> (opens in {PROVIDERS[item.provider].label})</span>
          </a>
          {onRemove && (
            <button
              type="button"
              aria-label={`Remove “${item.title}”`}
              onClick={() => onRemove(item.url)}
              className="flex h-7 w-7 shrink-0 items-center justify-center rounded-lg text-muted transition-colors hover:bg-wash hover:text-foreground focus-visible:outline-2 focus-visible:outline-foreground/30"
            >
              <HugeiconsIcon icon={Cancel01Icon} size={13} />
            </button>
          )}
        </li>
      ))}
    </ul>
  );
}
