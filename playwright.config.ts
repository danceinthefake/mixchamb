import { defineConfig } from "@playwright/test"

// End-to-end tests live beside the app they cover (single repo — no
// cross-repo version drift). They drive the real Phoenix app over a
// browser, so they're slower + heavier than the vitest unit tests and
// run as a separate CI job, never in the pre-commit hook.
//
// The dev server is the target (same setup the throwaway tmp/ smokes
// used + proven against). Locally it reuses an already-running
// `mix phx.server`; in CI Playwright boots one and waits on /up.
export default defineConfig({
  testDir: "./e2e",
  // Multiplayer flows open several browser contexts each + share one
  // dev server, so run them serially — parallel workers just contend
  // on the single server and flake.
  fullyParallel: false,
  workers: 1,
  retries: process.env.CI ? 1 : 0,
  forbidOnly: !!process.env.CI,
  reporter: process.env.CI ? [["list"], ["html", { open: "never" }]] : "list",
  timeout: 90_000,
  expect: { timeout: 12_000 },
  use: {
    baseURL: "http://localhost:4000",
    viewport: { width: 1280, height: 900 },
    trace: "retain-on-failure",
    screenshot: "only-on-failure",
  },
  webServer: {
    command: "mix phx.server",
    url: "http://localhost:4000/up",
    reuseExistingServer: !process.env.CI,
    timeout: 180_000,
  },
})
