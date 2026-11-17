/** Soft, slowly drifting colour glow behind the page. Purely decorative. */
export function Backdrop({ intensity = "full" }: { intensity?: "full" | "soft" }) {
  const opacity = intensity === "full" ? "opacity-70 dark:opacity-50" : "opacity-40 dark:opacity-30";

  return (
    <div aria-hidden="true" className="pointer-events-none fixed inset-0 -z-10 overflow-hidden">
      <div className={`absolute inset-0 ${opacity}`}>
        <div className="animate-drift absolute -left-[10%] -top-[20%] h-[60vmax] w-[60vmax] rounded-full bg-glow-1 blur-[120px]" />
        <div
          className="animate-drift absolute -right-[15%] top-[10%] h-[55vmax] w-[55vmax] rounded-full bg-glow-2 blur-[130px]"
          style={{ animationDelay: "-6s" }}
        />
        <div
          className="animate-drift absolute -bottom-[30%] left-[20%] h-[50vmax] w-[50vmax] rounded-full bg-glow-3 blur-[140px]"
          style={{ animationDelay: "-12s" }}
        />
      </div>
      {/* Fine dot grid keeps the glow from feeling like a flat gradient. */}
      <div className="absolute inset-0 bg-[radial-gradient(var(--card-border)_1px,transparent_1px)] [background-size:22px_22px] [mask-image:radial-gradient(ellipse_at_center,black_30%,transparent_75%)]" />
    </div>
  );
}
