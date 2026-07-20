import react from "@vitejs/plugin-react";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { defineConfig } from "vite";

const here = dirname(fileURLToPath(import.meta.url));
// The framework admin scaffold is imported from source (not a pnpm dependency edge): the app owns
// the single copy of react/react-admin, dedupe collapses any duplicate, and the root stays
// language-neutral. This is the source-level analog of the Dart path-dep into client/ (ADR-005).
const scaffoldEntry = resolve(here, "../../../admin/src/index.ts");
const repoRoot = resolve(here, "../../..");

// Backend target for the dev proxy. Honors ZEN_APP_PORT (the e2e/run:demo port strategy that
// dodges a leftover :8080 Supabase stack); defaults to Quarkus dev's :8080.
const backend = `http://localhost:${process.env.ZEN_APP_PORT ?? "8080"}`;

export default defineConfig({
  plugins: [react()],
  resolve: {
    alias: {
      "@jzen/admin-core": scaffoldEntry,
    },
    dedupe: ["react", "react-dom", "react-admin", "ra-data-simple-rest"],
  },
  server: {
    port: 5173,
    // Serve the scaffold source, which lives outside this app's root.
    fs: { allow: [repoRoot] },
    // Same-origin proxy so the httpOnly zen_access_token cookie flows without CORS juggling.
    proxy: {
      "/api": backend,
      "/openapi": backend,
    },
  },
});
