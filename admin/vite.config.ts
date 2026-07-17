import react from "@vitejs/plugin-react";
import { defineConfig } from "vite";

export default defineConfig({
  plugins: [react()],
  server: {
    port: 5173,
    // Quarkus dev mode. Keeps the admin panel same-origin so the session cookie
    // (zen_access_token) is sent without CORS credentials juggling.
    proxy: {
      "/api": "http://localhost:8080",
      "/openapi": "http://localhost:8080",
    },
  },
});
