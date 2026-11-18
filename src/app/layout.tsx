import type { Metadata } from "next";
import { Instrument_Sans } from "next/font/google";
import "./globals.css";

const sans = Instrument_Sans({
  variable: "--font-app-sans",
  subsets: ["latin"],
});

export const metadata: Metadata = {
  title: "Supervibes",
  description: "Supervibes",
};

export default function RootLayout({ children }: LayoutProps<"/">) {
  return (
    // The Mac app sets data-shell="mac" on <html> before React loads (see globals.css), so this
    // element's attributes can differ from the server's. Only <html> itself is exempted.
    <html lang="en" className={`${sans.variable} h-full`} suppressHydrationWarning>
      <body className="relative flex min-h-full flex-col">{children}</body>
    </html>
  );
}
