/** A quiet, cool backdrop: a faint top light and a fine grid that fades out. Decorative; fills the app's window. */
export function Backdrop() {
  return (
    <div aria-hidden="true" className="pointer-events-none absolute inset-0 -z-10 overflow-hidden">
      <div className="absolute inset-x-0 top-0 h-[480px] bg-[radial-gradient(60%_100%_at_50%_0%,var(--card)_0%,transparent_100%)] opacity-90" />
      <div className="absolute inset-0 bg-[linear-gradient(var(--card-border)_1px,transparent_1px),linear-gradient(90deg,var(--card-border)_1px,transparent_1px)] [background-size:56px_56px] [mask-image:radial-gradient(70%_50%_at_50%_0%,black,transparent)] opacity-60" />
    </div>
  );
}
