import { defineConfig, mergeConfig } from "vitest/config";
import viteConfig from "./vite.config";

// The panel's own Vite config (the @jzen/admin-core source alias and the React dedupe) plus a DOM,
// so a test renders the panel exactly as the build assembles it.
export default defineConfig((env) =>
  mergeConfig(viteConfig(env), {
    test: {
      environment: "jsdom",
      include: ["src/**/*.test.tsx"],
      setupFiles: ["src/test/setup.ts"],
    },
  }),
);
