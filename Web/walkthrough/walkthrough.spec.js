// Walks through the web version as a viewer would, against the demo server.
// Each test starts with an empty browser (no sign-ins, no preferences).
import { expect, test } from "@playwright/test";

const server = "127.0.0.1:8765";

/** Watches for anything the page refuses or throws: CSP blocks, crashes. */
function watchForProblems(page) {
  const problems = [];
  page.on("pageerror", (error) => problems.push("page error: " + error.message));
  page.on("console", (message) => {
    const text = message.text();
    if (/Content Security Policy|Refused to|Trusted Type|Fatal error/i.test(text)) problems.push(text);
  });
  return problems;
}

/** Signs in to the demo server with a made-up name, and waits for live TV. */
async function signIn(page) {
  await page.goto("/");
  await page.getByLabel("Server address").fill(server);
  await page.getByRole("button", { name: "Connect" }).click();
  await expect(page.getByRole("heading", { name: "Sign in" })).toBeVisible();
  await page.getByLabel("Username").fill("tester");
  await page.getByLabel("Password").fill("not-a-real-password");
  await page.getByRole("button", { name: "Sign In" }).click();
  await expect(page.locator(".now .channel-number")).not.toBeEmpty();
}

/** Live TV is on: a video is playing (its time goes on), or the channel
 *  is between programmes and says what's next (the Up next or station card).
 *  Given 45 s: a stream that stalls is retried by the player after 30 s
 *  (ChannelPlayer.stallTimeout), and that recovery counts. */
async function expectPlaying(page, streams = []) {
  const progress = () => page.evaluate(() => ({
    times: [...document.querySelectorAll("video")].map((video) => video.currentTime),
    card: document.querySelector(".status-card, .station-card") !== null,
  }));
  const start = await progress();
  const moving = async () => {
    const now = await progress();
    return now.card || now.times.some((time, index) => time > (start.times[index] ?? 0) + 0.5);
  };
  await expect.poll(moving, {
    timeout: 45_000,
    message: "live TV should play: " + JSON.stringify(streams) + " " + JSON.stringify(await page.evaluate(() => ({
      now: document.querySelector(".now")?.innerText.replace(/\n+/g, " | "),
      videos: [...document.querySelectorAll("video")].filter((v) => v.currentSrc)
        .map((v) => [v.className, v.paused, v.currentTime.toFixed(1), "rs" + v.readyState, "ns" + v.networkState, v.error?.code ?? null, v.currentSrc.split("/")[4]]),
      clock: document.querySelector(".now .clock")?.textContent,
      stopped: document.querySelector("dialog.confirm h2")?.textContent ?? null,
    }))),
  }).toBe(true);
}

test("signs in and plays live TV", async ({ page }) => {
  test.setTimeout(90_000);
  const problems = watchForProblems(page);
  // Diagnostics on (as Settings would keep it), and the video requests
  // noted, so a failure says what the player was doing.
  await page.addInitScript(() => localStorage.setItem("gregular.showsDiagnostics", JSON.stringify({ bool: { _0: true } })));
  const streams = [];
  page.on("request", (r) => { if (r.url().includes("/stream")) streams.push("asked " + r.url().split("/")[4]); });
  page.on("requestfinished", (r) => { if (r.url().includes("/stream")) streams.push("got " + r.url().split("/")[4]); });
  page.on("requestfailed", (r) => { if (r.url().includes("/stream")) streams.push("failed " + r.url().split("/")[4]); });
  let speedTests = 0;
  page.on("request", (r) => { if (r.url().includes("/Playback/BitrateTest")) speedTests++; });
  await signIn(page);
  await expectPlaying(page, streams);
  // Auto measures the connection only after trouble. A browser reporting
  // its position wrongly while it seeks once made the player think it was
  // far behind live and re-tune, with a speed test, every second.
  await page.waitForTimeout(5000);
  expect(speedTests).toBe(0);
  expect(problems).toEqual([]);
});

test("keeps the sign-in encrypted, and none of it in local storage", async ({ page }) => {
  await signIn(page);
  await page.reload();
  await expect(page.getByRole("heading", { name: "Your servers" })).toBeVisible();
  await expect(page.getByRole("button", { name: /Watch Demo Library/ })).toBeVisible();
  const stored = await page.evaluate(() => JSON.stringify({ ...localStorage }));
  expect(stored).not.toMatch(/accessToken|AccessToken|8765/);
  const vault = await page.evaluate(() => new Promise((resolve) => {
    const open = indexedDB.open("gregular");
    open.onsuccess = () => {
      const read = open.result.transaction("vault").objectStore("vault").get("sign-ins");
      read.onsuccess = () => resolve({ isBuffer: read.result.data instanceof ArrayBuffer,
                                       text: new TextDecoder().decode(read.result.data) });
    };
  }));
  expect(vault.isBuffer).toBe(true);
  expect(vault.text).not.toContain("accessToken");
});

test("the keyboard works the remote's tables", async ({ page }) => {
  await signIn(page);
  const number = page.locator(".now .channel-number");
  const first = await number.textContent();
  await page.keyboard.press("ArrowRight");
  await expect(number).not.toHaveText(first);
  // Escape hides the banner if it's up, otherwise opens the guide. (Overlays
  // ignore a second press within half a second: WatchModel.clickGuard.)
  const guide = page.getByRole("dialog", { name: "Guide" });
  for (let tries = 0; tries < 3 && !(await guide.isVisible()); tries++) {
    await page.keyboard.press("Escape");
    await page.waitForTimeout(700);
  }
  await expect(guide).toBeVisible();
  await expect(page.locator(".guide-cell:focus")).toHaveCount(1);
  await page.keyboard.press("Escape");          // up to Live TV
  await expect(page.getByRole("button", { name: "Live TV" })).toBeFocused();
  await page.keyboard.press("Escape");          // up to the main page
  await expect(page.getByRole("heading", { name: "Your servers" })).toBeVisible();
});

test("on a phone, every channel is under the picture", async ({ browser }) => {
  const context = await browser.newContext({ viewport: { width: 390, height: 844 }, hasTouch: true });
  const page = await context.newPage();
  await signIn(page);
  const lineup = page.getByRole("region", { name: "All channels" });
  await expect(lineup).toBeVisible();
  await lineup.getByRole("button", { name: /^Channel 10,/ }).click();
  await expect(page.locator(".now .channel-number")).toHaveText("10");
  await context.close();
});

test("Settings' switches say whether they're on", async ({ page }) => {
  await signIn(page);
  await page.keyboard.press("s");
  const diagnostics = page.getByRole("switch", { name: /Show playback diagnostics/ });
  await expect(diagnostics).toHaveAttribute("aria-checked", "false");
  await diagnostics.click();
  await expect(diagnostics).toHaveAttribute("aria-checked", "true");
  await expect(page.getByRole("radio", { name: /Auto/ })).toHaveAttribute("aria-checked", "true");
});
