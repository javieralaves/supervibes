import { useId } from "react";

export function LogoMark({ className = "h-9 w-9" }: { className?: string }) {
  const id = useId();

  return (
    <svg viewBox="0 0 40 40" className={className} aria-hidden="true">
      <defs>
        <linearGradient id={`${id}-fill`} x1="0" y1="0" x2="40" y2="40" gradientUnits="userSpaceOnUse">
          <stop offset="0" stopColor="var(--glow-1)" />
          <stop offset="0.55" stopColor="var(--glow-2)" />
          <stop offset="1" stopColor="var(--glow-3)" />
        </linearGradient>
      </defs>
      <rect width="40" height="40" rx="12" fill={`url(#${id}-fill)`} />
      <path
        d="M9 22.5c2.6-4.6 5.2-4.6 7.8 0s5.2 4.6 7.8 0 4.8-4.6 6.4-1.5"
        fill="none"
        stroke="white"
        strokeWidth="3"
        strokeLinecap="round"
      />
      <circle cx="29.5" cy="12" r="2.2" fill="white" opacity="0.9" />
    </svg>
  );
}

export function Wordmark({ size = "md" }: { size?: "md" | "lg" }) {
  return (
    <span className="flex items-center gap-2.5">
      <LogoMark className={size === "lg" ? "h-11 w-11" : "h-8 w-8"} />
      <span
        className={`font-semibold tracking-[-0.03em] text-foreground ${size === "lg" ? "text-2xl" : "text-lg"}`}
      >
        Supervibes
      </span>
    </span>
  );
}
