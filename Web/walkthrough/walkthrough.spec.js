// Walks through the web version as a viewer would, against the demo server.
// Each test starts with an empty browser (no sign-ins, no preferences).
import { readFile } from "node:fs/promises";
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

/** Signs in to the demo server with a made-up name, and waits for live TV.
 *  With `remember`, turns on Remember me on this browser first (it's off). */
async function signIn(page, { remember = false } = {}) {
  await page.goto("/");
  await page.getByLabel("Server address").fill(server);
  await page.getByRole("button", { name: "Connect" }).click();
  await expect(page.getByRole("heading", { name: "Sign in" })).toBeVisible();
  if (remember) await page.getByRole("switch", { name: /Remember me on this browser/ }).click();
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

/** The main page is on top, not under live TV's dimming or anything else
 *  of live TV's: what's at the middle of its heading is the heading. Live TV
 *  ignores the pointer while covered, so hit-testing would pass through it;
 *  for the test, it's made to catch the pointer again. */
async function expectMainPageOnTop(page) {
  const heading = page.getByRole("heading", { name: "Your servers" });
  await expect(heading).toBeVisible();
  const covering = await page.evaluate(() => {
    for (const element of document.querySelectorAll(".live, .live *")) {
      element.inert = false;
      element.style.pointerEvents = "auto";
    }
    const box = document.querySelector(".page-title").getBoundingClientRect();
    const top = document.elementFromPoint(box.x + box.width / 2, box.y + box.height / 2);
    return top?.closest(".page-layer") ? null : (top?.className || top?.tagName || "nothing");
  });
  expect(covering).toBeNull();
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

// Before anything loads, a browser reports a video it couldn't fetch at all
// as one it can't decode (MEDIA_ERR_SRC_NOT_SUPPORTED). That's the
// connection's trouble, so it's retried; it once said "can't be played".
test("a video the browser couldn't fetch is retried, not called unplayable", async ({ page }) => {
  test.setTimeout(90_000);
  const problems = watchForProblems(page);
  await page.addInitScript(() => {
    new MutationObserver(() => {
      if (/can.t be played/i.test(document.body?.innerText ?? "")) globalThis.saidUnplayable = true;
    }).observe(document, { subtree: true, childList: true, characterData: true });
  });
  // The first two stream requests fail outright: the video's, and (in a
  // browser that reports it as undecodable) the player's check of whether
  // the server can be reached at all.
  let refused = 0;
  await page.route(/\/stream/, (route) => (refused++ < 2 ? route.abort("connectionrefused") : route.continue()));
  await signIn(page);
  // Playing: a video's time moves on (it's set to the live position before it loads).
  const moving = () => page.evaluate(async () => {
    const times = () => [...document.querySelectorAll("video")].map((video) => (video.paused ? -1 : video.currentTime));
    const before = times();
    await new Promise((resolve) => setTimeout(resolve, 1000));
    return times().some((time, index) => before[index] >= 0 && time > before[index] + 0.5);
  });
  await expect.poll(moving, { timeout: 60_000, message: "the retry should play" }).toBe(true);
  expect(refused).toBeGreaterThanOrEqual(3);
  expect(await page.evaluate(() => globalThis.saidUnplayable ?? false)).toBe(false);
  expect(problems).toEqual([]);
});

test("keeps the sign-in encrypted, and none of it in local storage", async ({ page }) => {
  await signIn(page, { remember: true });
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

test("a sign-in isn't remembered unless asked, and lasts only until the page closes", async ({ page }) => {
  await page.goto("/");
  await page.getByLabel("Server address").fill(server);
  await page.getByRole("button", { name: "Connect" }).click();
  const remember = page.getByRole("switch", { name: /Remember me on this browser/ });
  await expect(remember).toHaveAttribute("aria-checked", "false");
  await page.getByLabel("Username").fill("tester");
  await page.getByLabel("Password").fill("not-a-real-password");
  await page.getByRole("button", { name: "Sign In" }).click();
  await expect(page.locator(".now .channel-number")).not.toBeEmpty();
  await page.reload();
  await expect(page.getByRole("heading", { name: "Connect to your server" })).toBeVisible();
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
  await expectMainPageOnTop(page);
});

test("the back arrow goes up to the main page, over live TV", async ({ page }) => {
  await signIn(page);
  await page.mouse.move(200, 200);              // the controls show
  await page.getByRole("button", { name: "All servers" }).click();
  await expectMainPageOnTop(page);
  await expect(page.getByText("Now playing")).toBeVisible();
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

test("on a phone, the channels under the picture follow a new schedule code", async ({ browser }) => {
  const context = await browser.newContext({ viewport: { width: 390, height: 844 }, hasTouch: true });
  const page = await context.newPage();
  await signIn(page);
  const lineup = () => page.locator(".lineup .row-programme").allTextContents();
  await expect.poll(async () => (await lineup()).length).toBeGreaterThan(0);
  const before = await lineup();
  // The channel list is made afresh each time it opens, so it has the channels as they are.
  const channelList = async () => {
    const rows = page.locator(".channel-list .row-programme");
    // Opening a panel just after another (Settings) is ignored for a moment: try again.
    await expect(async () => {
      await page.getByRole("button", { name: "Channel list" }).click();
      await expect(rows.first()).toBeVisible({ timeout: 1000 });
    }).toPass();
    const shown = await rows.allTextContents();
    await page.keyboard.press("Escape");
    return shown;
  };
  // Codes until one puts something else on (any one might happen not to).
  let after = before;
  for (const code of ["7KQM2-X9PDA", "11111-11111", "ZZZZZ-ZZZZZ", "00000-00000"]) {
    await enterCode(page, code);
    await expect(page.getByRole("dialog", { name: "Settings" })).toBeHidden();
    after = await channelList();
    if (after.join("\n") !== before.join("\n")) break;
  }
  expect(after).not.toEqual(before);
  await expect.poll(lineup).toEqual(after);
  await context.close();
});

test("a long channel list keeps every row whole", async ({ browser }) => {
  const context = await browser.newContext({ viewport: { width: 390, height: 844 }, hasTouch: true });
  const page = await context.newPage();
  await signIn(page);
  await page.getByRole("button", { name: "Channel list" }).click();
  await expect(page.getByRole("dialog", { name: "Channels" })).toBeVisible();
  // The demo server has two channels; a real one has many more. Copies of
  // the rows make the lists longer than the screen.
  const squeezed = await page.evaluate(() => {
    for (const list of document.querySelectorAll(".lineup, .channel-list .sheet-body")) {
      const rows = [...list.querySelectorAll(".channel-row")];
      for (let copy = 0; copy < 8; copy++) for (const row of rows) list.append(row.cloneNode(true));
    }
    return [...document.querySelectorAll(".channel-row")]
      .filter((row) => row.scrollHeight > row.clientHeight + 1).length;
  });
  expect(squeezed).toBe(0);
  await context.close();
});

test("times are in the viewer's time zone", async ({ browser }) => {
  // Far from GMT and from wherever the tests run.
  const context = await browser.newContext({ timezoneId: "Asia/Kolkata" });
  const page = await context.newPage();
  await signIn(page);
  const clock = page.locator(".now .clock");
  const local = () => page.evaluate(() =>
    new Intl.DateTimeFormat("en-US", { hour: "numeric", minute: "2-digit" }).format(new Date()).match(/\d+:\d\d/)[0]);
  await expect.poll(async () => (await clock.textContent()).match(/\d+:\d\d/)?.[0] === (await local())).toBe(true);
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

/** Types `code` where a schedule code goes, in Settings. */
async function enterCode(page, code) {
  const field = page.getByLabel("Enter a code, like 7KQM2-X9PDA");
  // Opening Settings just after another panel closed is ignored for a moment: try again.
  await expect(async () => {
    await page.keyboard.press("s");
    await expect(field).toBeVisible({ timeout: 1000 });
  }).toPass();
  await field.fill(code);
  await field.press("Enter");
}

// Karaoke's keyword, from SPECIAL_MODE_KEYWORD: the repo keeps only its
// hash, so the keyword itself is never written here.
const keyword = process.env.SPECIAL_MODE_KEYWORD ?? "";

test("a keyword opens karaoke, which sings and goes back to live TV", async ({ page }) => {
  test.skip(!keyword, "Set SPECIAL_MODE_KEYWORD to walk through karaoke");
  test.setTimeout(90_000);
  const problems = watchForProblems(page);
  const songs = [];
  page.on("request", (r) => { if (r.url().includes("/Audio/")) songs.push(new URL(r.url()).pathname); });
  await signIn(page);
  await enterCode(page, keyword);
  await expect(page.getByRole("heading", { name: "Pick a Theme" })).toBeVisible();

  // A highlighted box samples its theme across the page; choosing it goes on.
  const karaoke = page.locator("main.karaoke");
  await page.keyboard.press("ArrowRight");
  await expect(karaoke).toHaveAttribute("data-theme", "karaokeBar");
  await page.keyboard.press("Enter");
  await expect(page.getByRole("heading", { name: "Karaoke" })).toBeVisible();

  await page.getByRole("button", { name: "All Songs" }).click();
  await expect(page.locator(".k-list .k-item")).toHaveCount(15);
  await expect(page.locator(".k-item", { hasText: "Splash Dance" }).locator(".k-badge")).toHaveText("Video");
  await expect(page.locator(".k-item", { hasText: "Hum Along" }).locator(".k-badge")).toHaveText("No lyrics");
  await page.locator(".k-item", { hasText: "Saturday Satellite" }).click();

  // Loaded whole, from memory, then held on its title card for Play.
  await expect(page.getByRole("button", { name: "Press Play to sing" })).toBeVisible();
  expect(await page.locator("video.song-video").evaluate((video) => video.currentSrc)).toMatch(/^blob:/);
  expect(songs.filter((path) => path.includes("/stream"))).toEqual(["/Audio/song0/stream.m4a"]);
  await page.keyboard.press(" ");
  const current = page.locator(".k-line-current");
  await expect(current).toHaveText("Spin me round the satellite", { timeout: 10_000 });
  // The words light up as they're sung, and the ball bounces over them.
  await expect.poll(() => current.locator(".k-word").first().evaluate((word) => Number(word.style.getPropertyValue("--fill"))))
    .toBeGreaterThan(0);
  await expect(page.locator(".k-ball")).toBeVisible();

  // Escape: karaoke's menu, over the song. Only Leave Karaoke leaves.
  await page.keyboard.press("Escape");
  await expect(page.getByRole("button", { name: "Back to the Song" })).toBeVisible();
  await page.getByRole("button", { name: "Leave Karaoke" }).click();
  await page.getByRole("dialog").getByRole("button", { name: "Leave Karaoke" }).click();
  await expect(page.locator(".now .channel-number")).not.toBeEmpty();
  await expect(karaoke).toHaveCount(0);
  expect(problems).toEqual([]);
});

test("karaoke's queue: the next song loads while one plays, and the queue runs out to the attract screen", async ({ page }) => {
  test.skip(!keyword, "Set SPECIAL_MODE_KEYWORD to walk through karaoke");
  test.setTimeout(90_000);
  await signIn(page);
  await enterCode(page, keyword.toUpperCase());
  await page.locator(".k-theme-box").first().click();
  await page.getByRole("button", { name: "All Songs" }).click();
  await page.locator(".k-item", { hasText: "Moonlight Microphone" }).click();
  await expect(page.getByRole("button", { name: "Press Play to sing" })).toBeVisible();
  await page.keyboard.press(" ");
  await page.keyboard.press("Escape");
  await page.getByRole("button", { name: "All Songs" }).click();
  await page.locator(".k-item", { hasText: "Splash Dance" }).click();
  await expect(page.locator(".k-notice")).toHaveText(/Splash Dance.*is next/);
  await page.keyboard.press("Escape");
  await page.getByRole("button", { name: /Queue/ }).click();
  await expect(page.locator(".k-queue-item")).toHaveText([/Splash Dance/]);
  await page.getByRole("button", { name: "Remove Splash Dance" }).click();
  await expect(page.getByText("No songs in the queue yet.")).toBeVisible();
  await page.keyboard.press("Escape");
  await page.getByRole("button", { name: "Skip This Song" }).click();
  // Nothing left: the attract screen, which any key leaves for the menu.
  await expect(page.getByText("Pick a song!")).toBeVisible();
  await page.keyboard.press("ArrowDown");
  await expect(page.getByRole("button", { name: "Artists" })).toBeVisible();
});

// Clicked rather than tapped, as in the other phone tests: WebKit on a
// computer doesn't make a tap into a click, as a phone's does.
test("karaoke fits a phone", async ({ browser }) => {
  test.skip(!keyword, "Set SPECIAL_MODE_KEYWORD to walk through karaoke");
  const context = await browser.newContext({ viewport: { width: 390, height: 844 }, hasTouch: true });
  const page = await context.newPage();
  await signIn(page);
  await enterCode(page, keyword.toLowerCase());
  const boxes = page.locator(".k-theme-box");
  await expect(boxes).toHaveCount(4);
  const [first, second] = [await boxes.nth(0).boundingBox(), await boxes.nth(1).boundingBox()];
  expect(second.y).toBeGreaterThan(first.y + first.height - 1);   // one above another
  await boxes.nth(2).click();
  await expect(page.locator("main.karaoke")).toHaveAttribute("data-theme", "bubblegumPop");
  await page.getByRole("button", { name: "Artists" }).click();
  await page.locator(".k-item", { hasText: "The Tin Canaries" }).click();
  await expect(page.getByRole("heading", { name: "The Tin Canaries" })).toBeVisible();
  const overflow = await page.evaluate(() => document.scrollingElement.scrollWidth - innerWidth);
  expect(overflow).toBeLessThanOrEqual(0);
  await page.getByRole("button", { name: "Back" }).click();
  await expect(page.getByRole("heading", { name: "Artists" })).toBeVisible();
  await context.close();
});

// The editing page's own script and the one it shares with every page the
// Apple TV serves (local-page.js) both load, and it asks this app directly.
test("the channel editor opens and makes a channel", async ({ page }) => {
  const problems = watchForProblems(page);
  await signIn(page);
  await page.keyboard.press("s");
  await page.getByRole("button", { name: "Edit Channels" }).click();
  const editor = page.frameLocator("iframe[title='Your channels and set times']");
  await editor.getByRole("button", { name: "Add a Channel" }).click();
  await expect(editor.getByText("Not saved yet.")).toBeVisible();
  // A year range narrows the channel ("All of"), rather than adding a decade to it.
  await editor.getByLabel("Condition").selectOption("years");
  await expect(editor.getByLabel("Join")).toHaveValue("allOf");
  await editor.getByLabel("First year").fill("1990");
  await editor.getByLabel("Last year").fill("1999");
  await editor.getByRole("button", { name: "Add Condition" }).click();
  await expect(editor.getByText("All of:")).toBeVisible();
  await expect(editor.getByText("Years: 1990–1999")).toBeVisible();
  expect(problems).toEqual([]);
});

/** Opens the channel editor's Feeds tab, follows the feed at `link` in
 *  channels 60–69 (after `looking` at its preview), and returns the editor's frame. */
async function followFeed(page, link, looking = async () => {}) {
  await page.keyboard.press("s");
  await page.getByRole("button", { name: "Edit Channels" }).click();
  const editor = page.frameLocator("iframe[title='Your channels and set times']");
  await editor.getByRole("button", { name: "Feeds" }).click();
  await editor.getByLabel("Feed link").fill(link);
  await editor.getByRole("button", { name: "Look" }).click();
  await looking(editor);
  await editor.getByLabel("Channel numbers").selectOption("60");
  await editor.getByRole("button", { name: "Follow", exact: true }).click();
  await expect(editor.getByText("Up to date.")).toBeVisible();
  return editor;
}

// A feed is followed from the channel editor (looked at first, like a
// podcast's page), listed in Settings, and unfollowed there.
test("a feed is followed, listed and unfollowed", async ({ page }) => {
  const problems = watchForProblems(page);
  await signIn(page);
  const editor = await followFeed(page, `http://${server}/feeds/silent-comedy.json`, async (editor) => {
    await expect(editor.getByRole("heading", { name: "Silent Laughs" })).toBeVisible();
    await expect(editor.getByText("From The Demo Library")).toBeVisible();
  });
  await expect(editor.getByText("Following Silent Laughs.")).toBeVisible();
  await expect(editor.getByText(/^61 {2}Silent Comedy/)).toBeVisible();
  // In Settings, behind the editor: the feed, and Unfollow.
  await page.getByRole("button", { name: "Close" }).last().click();
  const settings = page.locator(".settings");
  await expect(settings.getByText("Silent Laughs")).toBeVisible();
  await expect(settings.getByText("Channels 60–69 · Up to date.")).toBeVisible();
  await settings.getByRole("button", { name: "Unfollow" }).click();
  await page.getByRole("button", { name: "Unfollow" }).last().click();
  await expect(settings.getByText("You don't follow any feeds.")).toBeVisible();
  expect(problems).toEqual([]);
});

// A feed that changes after it's followed (the demo server's changing feed):
// opening the app again checks it, Settings gets its dot and the update's
// lines, and one tap brings the update in, with the feed's picture.
test("a feed's update comes in with one tap", async ({ page, browserName }) => {
  const problems = watchForProblems(page);
  await signIn(page);
  await followFeed(page, `http://${server}/feeds/changing/${browserName}-${Date.now()}.json`);
  await signIn(page);   // opens the app again
  const news = page.locator(".has-news");
  await expect(news.first()).toHaveAttribute("aria-description", "A feed has an update.");
  await page.keyboard.press("s");
  const settings = page.locator(".settings");
  await expect(settings.getByText("Channels 60–69 · Update available.")).toBeVisible();
  await expect(settings.getByText("New channel: Silent Adventures")).toBeVisible();
  await expect(settings.locator(".feed-badge")).toHaveText("SL");
  await settings.getByRole("button", { name: /Get Update/ }).click();
  await expect(settings.getByText("Channels 60–69 · Up to date.")).toBeVisible();
  const picture = settings.locator("img.feed-art");
  await expect(picture).toBeVisible();
  expect(await picture.evaluate((image) => image.naturalWidth)).toBe(48);
  await expect(news).toHaveCount(0);
  await settings.getByRole("button", { name: "Unfollow" }).click();
  await page.getByRole("button", { name: "Unfollow" }).last().click();
  await expect(settings.getByText("You don't follow any feeds.")).toBeVisible();
  expect(problems).toEqual([]);
});

// Share as a feed on a phone: a picture chosen (with a long file name, as a
// phone's camera gives) keeps within the page, goes in the file, and can be
// removed again before the file is made.
test("a feed's picture fits a phone, and can be removed", async ({ browser }) => {
  const context = await browser.newContext({ viewport: { width: 390, height: 844 }, hasTouch: true });
  const page = await context.newPage();
  const problems = watchForProblems(page);
  await signIn(page);
  const editor = await followFeed(page, `http://${server}/feeds/silent-comedy.json`);
  await editor.getByRole("button", { name: "Make a Copy" }).click();
  await editor.getByRole("button", { name: "Save", exact: true }).click();
  await expect(editor.getByText("Saved. Your channels have been rebuilt.")).toBeVisible();
  await editor.getByLabel("Feed name").fill("Pictured");
  const picture = editor.getByLabel("Picture", { exact: true });
  await picture.setInputFiles({ name: "IMG_20261026_201512_a_picture_with_a_long_name_from_a_phone.png", mimeType: "image/png",
    buffer: Buffer.from("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==", "base64") });
  const overflow = () => editor.locator("body").evaluate(() => document.scrollingElement.scrollWidth - innerWidth);
  expect(await overflow()).toBeLessThanOrEqual(0);
  const madeFile = async () => {
    const download = page.waitForEvent("download");
    await editor.getByRole("button", { name: "Save Feed File" }).click();
    return JSON.parse(await readFile(await (await download).path(), "utf8"));
  };
  expect((await madeFile()).image).toBeTruthy();

  const remove = editor.getByRole("button", { name: "Remove Picture" });
  await remove.click();
  await expect(picture).toHaveValue("");
  await expect(remove).toBeHidden();
  expect((await madeFile()).image).toBeUndefined();
  expect(await overflow()).toBeLessThanOrEqual(0);
  expect(problems).toEqual([]);
  await context.close();
});

// A feed's channel copied to your own (with its set times), saved, and that
// block of your channels shared as a feed file, which downloads.
test("a feed's channel is copied, and your channels are shared as a feed", async ({ page }) => {
  const problems = watchForProblems(page);
  await signIn(page);
  const editor = await followFeed(page, `http://${server}/feeds/silent-comedy.json`);
  await editor.getByRole("button", { name: "Make a Copy" }).click();
  await expect(editor.getByText("Copied to your channel 20. Save to keep it.")).toBeVisible();
  await editor.getByRole("button", { name: "Save", exact: true }).click();
  await expect(editor.getByText("Saved. Your channels have been rebuilt.")).toBeVisible();

  await editor.getByLabel("Channels to share").selectOption("20");
  await editor.getByLabel("Feed name").fill("Copied Laughs");
  await editor.getByLabel("Publisher").fill("A Tester");
  const download = page.waitForEvent("download");
  await editor.getByRole("button", { name: "Save Feed File" }).click();
  const file = await download;
  expect(file.suggestedFilename()).toBe("copied-laughs.json");
  const feed = JSON.parse(await readFile(await file.path(), "utf8"));
  expect(feed).toMatchObject({ gregularFeed: 1, title: "Copied Laughs", publisher: "A Tester", timeZone: "local" });
  expect(feed.channels.map((channel) => [channel.number, channel.name])).toEqual([[20, "Silent Comedy"]]);
  expect(feed.setTimes.map((times) => times.channel)).toEqual([20]);
  await expect(editor.getByLabel("The feed file")).toHaveValue(/"Copied Laughs"/);
  expect(problems).toEqual([]);
});

