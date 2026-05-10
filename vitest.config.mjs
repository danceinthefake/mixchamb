import { defineConfig } from "vitest/config";
import vue from "@vitejs/plugin-vue";
import { fileURLToPath, URL } from "node:url";

// Vitest config — separate from assets/vite.config.mjs so the
// build pipeline isn't entangled with the test runner. Tests
// live under assets/vue/__tests__/ and use the same `@/...`
// alias the production code imports through.
export default defineConfig({
  plugins: [vue()],
  resolve: {
    alias: {
      "@": fileURLToPath(new URL("./assets/vue", import.meta.url)),
    },
  },
  test: {
    environment: "happy-dom",
    include: ["assets/vue/**/*.{test,spec}.{ts,js}"],
    globals: true,
    css: false,
    coverage: {
      provider: "v8",
      // json-summary is the slim machine-readable file the
      // badge script parses; text gives a CLI summary too.
      reporter: ["text", "json-summary"],
      include: ["assets/vue/**/*.{ts,vue}"],
      exclude: ["assets/vue/**/__tests__/**", "assets/vue/components/ui/**"],
    },
  },
});
