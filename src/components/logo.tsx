export function LogoMark({ className = "h-9 w-9" }: { className?: string }) {
  return (
    <svg viewBox="0 0 40 40" className={className} aria-hidden="true">
      <rect width="40" height="40" rx="11" fill="var(--foreground)" />
      <path
        d="M9 22.5c2.6-4.6 5.2-4.6 7.8 0s5.2 4.6 7.8 0 4.8-4.6 6.4-1.5"
        fill="none"
        stroke="var(--background)"
        strokeWidth="3"
        strokeLinecap="round"
      />
      <circle cx="29.5" cy="12" r="2.2" fill="var(--background)" opacity="0.7" />
    </svg>
  );
}

export function Wordmark({ size = "md" }: { size?: "md" | "lg" }) {
  return (
    <span className="flex items-center gap-2.5">
      <LogoMark className={size === "lg" ? "h-10 w-10" : "h-8 w-8"} />
      <span
        className={`font-semibold tracking-[-0.03em] text-foreground ${size === "lg" ? "text-xl" : "text-lg"}`}
      >
        Supervibes
      </span>
    </span>
  );
}
