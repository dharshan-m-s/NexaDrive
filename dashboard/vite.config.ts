import { defineConfig } from "vitest/config";
import react from "@vitejs/plugin-react";

// The dashboard is built to static files and served by the Rust server from
// `dashboard/dist`. During development the Vite dev server proxies the console
// API to the loopback-only console listener (default 127.0.0.1:8090).
export default defineConfig({
  plugins: [react()],
  server: {
    host: "127.0.0.1",
    port: 5173,
    proxy: {
      "/api": "http://127.0.0.1:8090",
    },
  },
  build: {
    outDir: "dist",
    sourcemap: false,
  },
  test: {
    environment: "node",
  },
});