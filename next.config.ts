import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  cacheComponents: true,
  experimental: {
    // The icon package re-exports ~15k icons from one index; only load the ones we import.
    optimizePackageImports: ["@hugeicons/core-free-icons"],
  },
  partialPrefetching: true,
};

export default nextConfig;
