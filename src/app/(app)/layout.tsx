import { Backdrop } from "@/components/backdrop";
import { AppRail } from "@/components/rail/app-rail";

/** Signed-in app shell: the left rail plus the page. */
export default function AppLayout({ children }: LayoutProps<"/">) {
  return (
    <>
      <AppRail />
      <div className="flex min-h-dvh flex-1 flex-col pl-16">
        <Backdrop />
        {children}
      </div>
    </>
  );
}
