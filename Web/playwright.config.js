// The web version's walkthrough (scripts/test-web.sh walkthrough), in
// Chromium, WebKit and Firefox, against the demo server (scripts/demo-server.py),
// which signs anyone in. Serves Web/dist with gregular.tv's headers.
import { defineConfig, devices } from "@playwright/test";

export default defineConfig({
  testDir: "walkthrough",
  timeout: 60_000,
  expect: { timeout: 15_000 },
  fullyParallel: false,
  workers: 1,
  // One more try on GitHub's runners, where a page now and then takes over
  // a minute to load for reasons of their own; none locally, where a
  // failure is always worth looking at. A test passing only on its retry
  // still shows as "flaky" in the report.
  retries: process.env.CI ? 1 : 0,
  reporter: [["list"]],
  use: { baseURL: "http://localhost:8090", trace: "off" },
  projects: [
    { name: "chromium", use: { ...devices["Desktop Chrome"] } },
    { name: "webkit", use: { ...devices["Desktop Safari"] } },
    { name: "firefox", use: { ...devices["Desktop Firefox"] } },
  ],
  webServer: [
    { command: "python3 ../scripts/demo-server.py", url: "http://127.0.0.1:8765/System/Info/Public", reuseExistingServer: true },
    { command: "PORT=8090 python3 ../scripts/serve-web.py", url: "http://localhost:8090/", reuseExistingServer: true },
  ],
});
