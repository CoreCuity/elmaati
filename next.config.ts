import type { NextConfig } from "next";
import path from "node:path";
import { fileURLToPath } from "node:url";

// This app lives inside the CoreCuity monorepo, which has its own root
// package-lock.json. Pin the workspace/file-tracing root to THIS directory so
// Next.js doesn't infer the HQ repo root and trace the whole monorepo.
const projectRoot = path.dirname(fileURLToPath(import.meta.url));

const nextConfig: NextConfig = {
  outputFileTracingRoot: projectRoot,
  turbopack: {
    root: projectRoot,
  },
};

export default nextConfig;
