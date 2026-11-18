import { Backdrop } from "@/components/backdrop";
import { AppRail } from "@/components/rail/app-rail";

/**
 * Signed-in app shell: the rail sits on the shell colour, and every page lives in one
 * window inset from the edges by a small, even gap. The window scrolls, not the page,
 * so the rail and the gap stay put. Scrolling code looks it up by [data-shell-scroll].
 *
 * Inside the Mac app, which draws its own rail and window, [data-app-rail] is hidden and
 * [data-app-window] fills the view (see html[data-shell="mac"] in globals.css).
 */
export default function AppLayout({ children }: LayoutProps<"/">) {
  return (
    <div className="flex h-dvh bg-shell">
      <AppRail />
      <div
        data-app-window
        className="relative isolate my-2 mr-2 flex min-w-0 flex-1 flex-col overflow-hidden rounded-xl border border-card-border bg-background shadow-[0_1px_3px_rgb(15_17_20/0.05)]"
      >
        <Backdrop />
        <div data-shell-scroll className="flex min-h-0 flex-1 flex-col overflow-y-auto overscroll-contain">
          {children}
        </div>
      </div>
    </div>
  );
}
