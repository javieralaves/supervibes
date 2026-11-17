/* eslint-disable @next/next/no-img-element */
import type { ProviderKey } from "@/lib/providers";

/*
 * Real app icons for connected apps.
 * Linear and GitHub marks: Simple Icons (CC0). Granola: its own app icon, public/brands/granola.png.
 */
const LINEAR_PATH = "M2.886 4.18A11.982 11.982 0 0 1 11.99 0C18.624 0 24 5.376 24 12.009c0 3.64-1.62 6.903-4.18 9.105L2.887 4.18ZM1.817 5.626l16.556 16.556c-.524.33-1.075.62-1.65.866L.951 7.277c.247-.575.537-1.126.866-1.65ZM.322 9.163l14.515 14.515c-.71.172-1.443.282-2.195.322L0 11.358a12 12 0 0 1 .322-2.195Zm-.17 4.862 9.823 9.824a12.02 12.02 0 0 1-9.824-9.824Z";
const GITHUB_PATH = "M12 .297c-6.63 0-12 5.373-12 12 0 5.303 3.438 9.8 8.205 11.385.6.113.82-.258.82-.577 0-.285-.01-1.04-.015-2.04-3.338.724-4.042-1.61-4.042-1.61C4.422 18.07 3.633 17.7 3.633 17.7c-1.087-.744.084-.729.084-.729 1.205.084 1.838 1.236 1.838 1.236 1.07 1.835 2.809 1.305 3.495.998.108-.776.417-1.305.76-1.605-2.665-.3-5.466-1.332-5.466-5.93 0-1.31.465-2.38 1.235-3.22-.135-.303-.54-1.523.105-3.176 0 0 1.005-.322 3.3 1.23.96-.267 1.98-.399 3-.405 1.02.006 2.04.138 3 .405 2.28-1.552 3.285-1.23 3.285-1.23.645 1.653.24 2.873.12 3.176.765.84 1.23 1.91 1.23 3.22 0 4.61-2.805 5.625-5.475 5.92.42.36.81 1.096.81 2.22 0 1.606-.015 2.896-.015 3.286 0 .315.21.69.825.57C20.565 22.092 24 17.592 24 12.297c0-6.627-5.373-12-12-12";

const SIZES = {
  xs: { box: "h-[18px] w-[18px] rounded-[5px]", mark: 11 },
  sm: { box: "h-6 w-6 rounded-md", mark: 14 },
  md: { box: "h-10 w-10 rounded-xl", mark: 22 },
};

function Tile({ className, children }: { className: string; children: React.ReactNode }) {
  return (
    <span aria-hidden="true" className={`inline-flex shrink-0 items-center justify-center overflow-hidden ${className}`}>
      {children}
    </span>
  );
}

function Mark({ path, size }: { path: string; size: number }) {
  return (
    <svg viewBox="0 0 24 24" width={size} height={size} fill="white">
      <path d={path} />
    </svg>
  );
}

export function ProviderMark({ provider, size = "md" }: { provider: ProviderKey; size?: keyof typeof SIZES }) {
  const s = SIZES[size];
  switch (provider) {
    case "linear":
      return (
        <Tile className={`${s.box} bg-[#5e6ad2]`}>
          <Mark path={LINEAR_PATH} size={s.mark} />
        </Tile>
      );
    case "github":
      return (
        <Tile className={`${s.box} bg-[#181717] ring-1 ring-inset ring-white/10`}>
          <Mark path={GITHUB_PATH} size={s.mark} />
        </Tile>
      );
    case "granola":
      return (
        <Tile className={s.box}>
          <img src="/brands/granola.png" alt="" className="h-full w-full" />
        </Tile>
      );
  }
}
