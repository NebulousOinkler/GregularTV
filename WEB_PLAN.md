# Gregular TV on the web: plan, and hosting at gregular.tv

Planned and built 2026-10-02. **Status:** phases 0 to 5 are done in code (`Web/`), except the hosting steps marked **(you)**, which need the domain owner's accounts. Decided: Chrome-only for http servers, views in Swift, Cloudflare. Design direction: mobile first (phone readability and accessibility leading, then larger screens), with a design of its own rather than the Apple TV's. See *What building it found*, at the end.

## The four decisions everything else follows from

**1. Reuse the Swift code by compiling it to WebAssembly.**
- Swift 6.2 and later can build for the browser with the official WebAssembly SDKs from swift.org. JavaScriptKit (a Swift library for working with the browser's JavaScript) lets Swift drive the page directly.
- The package was already laid out for this. `Package.swift` says "A web version would reuse the first three and bring its own views, PlayerDeck, HTTPTransport and CredentialStore."
- So GregularCore (the scheduling), GregularJellyfin (the server connection) and GregularScreens (what each screen does) run in the browser with the same behaviour. That is about 7,000 of the 12,700 lines.
- Only the tvOS front end is replaced: the SwiftUI views, `AVPlayerDeck`, `KeychainStore` and `URLSessionTransport`.
- Write the web views in Swift too, not TypeScript. Otherwise every model's shape would exist twice, in two languages.

**2. No server of our own.** gregular.tv only serves static files. The browser talks to the user's Jellyfin server directly, and video goes straight from Jellyfin to the browser. This is the only design that keeps the privacy rule: gregular.tv never sees a server address, token, library or stream, because nothing is ever sent to it.

**3. Video plays in `<video>` elements.**
- Jellyfin sends video as HLS. Safari plays it natively; the other browsers need hls.js, a player library. It is hosted on gregular.tv itself, not loaded from a third party.
- Two video elements copy what the Apple TV does now: one on screen, and one behind it preparing the programme after a commercial break.

**4. Browsers block an https page from talking to an http server.** gregular.tv must be https, so this is the hardest product limit:

| User's server | Chrome / Edge 142+ | Safari, Firefox |
|---|---|---|
| `https://…` (reverse proxy, Tailscale HTTPS, etc.) | ✅ | ✅ |
| `http://192.168.x.x`, `http://name.local` | ✅ after the browser asks for "local network" permission (confirm in phase 0) | ❌ blocked |
| `http://jellyfin:8096` (a bare name) | ✅ if requests are marked as local network traffic (`targetAddressSpace: "local"`) | ❌ |

- Chrome's local network permission explicitly allows this for `fetch()` calls.
- Phase 0 must confirm that video loading through hls.js is allowed too. hls.js can be set to load through `fetch()`, which should make it work.
- Safari and Firefox users with an http server get a plain explanation and the options: use https, or use Chrome.
- Jellyfin accepts requests from other websites by default (its CORS hosts setting is `*`). If an administrator has narrowed that list, they add `https://gregular.tv`.

## Changes to the shared code first

These are refactors only. The tvOS app keeps the same behaviour, and the tests must stay green.

| Change | Why |
|---|---|
| Replace `URLRequest`/`HTTPURLResponse` in `HTTPTransport` with small request and reply types of our own. `URLSessionTransport` converts to them, and moves behind a check so it only builds on Apple platforms. | URLSession's networking library (FoundationNetworking) likely isn't available on WebAssembly, and the protocol uses its types. |
| Make `DeviceProfile` in `Playback.swift` take a parameter for the platform. tvOS keeps its current profile. The browser profile: direct play of mp4 with H.264 and AAC; HLS that converts to H.264 first; AAC audio only; HEVC only if `MediaSource.isTypeSupported` says the browser can play it. | Browsers can't play AC-3/E-AC-3 audio or MKV files. The subtitle rules (`External`, `SubtitleStreamIndex=-1`) stay as they are. |
| Add a small key-value storage protocol under `AppPreferences`: `UserDefaults` on Apple, `localStorage` on the web. | It is Core's only use of `UserDefaults`. |
| Build `channels.json` into the code with SwiftPM's `.embedInCode` instead of `Bundle.module`. | A browser has no bundle to read files from. |
| Pass launch options (`DemoCredentials`, `DebugOptions`) in from outside instead of reading `ProcessInfo.arguments`. | The web reads them from the page URL. |
| Move the text still written in the SwiftUI views into GregularScreens, the way `LoginModel` already holds its text. | Both front ends then use the same words, and the duplication check covers them. |
| Split `EditingPage` into the home-network protections (host, origin, code) and the request answers. Have `EditingPageHTML` send requests through a function the host page provides. | The web reuses the editing page as its own channel editor, calling the answers directly, with no network in between. |
| Turn `RemoteControls.debugKeys` into a supported keyboard map. | The web uses it for the arrow keys, Enter, Escape (Menu), Space (play/pause) and number keys. |

## New code for the web

- **A new target, `GregularWeb`, written in Swift:**
  - **Network requests.** `FetchTransport`, a transport built on `fetch()`:
    - It refuses redirects (`redirect: "error"`), which is stricter than `TransportRules`.
    - It sends no cookies or saved logins (`credentials: "omit"`) and caches nothing (`cache: "no-store"`).
    - It reads replies in chunks and stops at `TransportRules.largestResponse`.
    - Cancelling a request aborts it (`AbortController`).
    - It marks requests to http servers as local network traffic.
  - **Video.** `VideoDeck`, which fits the existing `PlayerDeck` protocol, using two `<video>` elements plus hls.js. The browser's video events provide what the protocol asks for: buffering, failures, `bufferedAhead`, `bufferedInAll` and `activity`.
  - **Sound on first play.** The user's first "Watch" click allows sound on both video elements, because browsers block autoplay with sound until the user interacts.
  - **Views.** Swift views that re-draw the page whenever a GregularScreens model changes (`withObservationTracking`). Text is always inserted as text, never as HTML, which `Package.swift` already requires.
  - **The screens:** sign-in (including Quick Connect), the main page, the watch screen (banner, overlays, curtain, station card, Up next card), the guide, the channel list, settings, and the channel editor reused from the editing page.
  - **Browser extras:** full screen, keyboard play/pause through Media Session, keeping the screen awake while watching (Wake Lock), and touch on phones.
  - **View framework.** Try ElementaryUI, a small SwiftUI-like web library, in phase 0. If it isn't mature enough, write a small renderer of our own. Don't use Tokamak: it is unmaintained.
- **A separate target for saved sign-ins, `GregularBrowserStore`.** It mirrors `GregularKeychain`'s dependencies: it depends on GregularJellyfin, and the web app never imports GregularJellyfin directly.
  - Sign-ins are saved in IndexedDB, the browser's built-in database. Tokens are encrypted with a WebCrypto key that page code can't extract.
  - The limit: this protects copies stored on disk. Script running on the page could still use the token. The real defence is the strict security headers below.
  - Settings gets a "Forget everything in this browser" button. It replaces the tvOS first-launch wipe.
- **A `Web/` folder:** `index.html`, the CSS, hls.js, the brand artwork and the station card sound, plus a `_headers` file that sets:
  - Content Security Policy: `default-src 'none'`; `script-src 'self' 'wasm-unsafe-eval'`; `connect-src` and `media-src` set to `https: http: blob:` (the user's own servers); `worker-src blob:` (for hls.js); `frame-ancestors 'self'` (only the app frames its channel editor); `base-uri 'none'`; `form-action 'none'`.
  - Trusted Types (`require-trusted-types-for 'script'`), `Referrer-Policy: no-referrer`, a Permissions-Policy, and COOP `same-origin`.

## Privacy and security carried over

- There is still no analytics, crash reporting, third-party script or font, or anything else sent anywhere but the user's own server.
- `privacy-check.sh` is extended to check `Web/` as well.
- Everything the tvOS app does already applies on the web: per-sign-in device IDs, the administrator warning, http only on the local network (`ServerAddress.isAllowed`), the 401/403 handling, and the size limits.
- `layer-check.sh` gains the rules for the new web targets: GregularWeb never imports GregularJellyfin; only GregularBrowserStore does.

## Testing

- The existing package and app tests keep running.
- A new `scripts/test-web.sh`, run through `bounded.sh`:
  - It compiles GregularCore, GregularJellyfin and GregularScreens for WebAssembly.
  - It runs the Core and Jellyfin tests under wasmtime.
  - It runs a Playwright walkthrough against `scripts/demo-server.py` in Chromium, WebKit and Firefox.
- The new transport is added to `TransportConformanceTests`, and the new store is checked with `CredentialStoreRules`.

## Phases

| Phase | Done when |
|---|---|
| 0. Prototype, one throwaway branch, no merge | The shared code compiles for WebAssembly. The download size is measured: Foundation's time-zone data (ICU) is the biggest risk, and the target is under about 10 MB compressed. `America/Los_Angeles` resolves. One HLS stream plays from an https server, and one from an http LAN server in Chrome. The view framework is chosen. **Go or no-go.** |
| 1. Shared refactors | The tvOS app is unchanged and all tests pass. |
| 2. Web platform pieces | `FetchTransport` passes `TransportConformanceTests`. `GregularBrowserStore` passes `CredentialStoreRules`. `VideoDeck` has its own tests. |
| 3. Screens | The browser walkthrough passes in all three browsers. |
| 4. Polish | Keyboard and touch, full screen, accessibility, TV browsers. |
| 5. Release | Deployment from GitHub Actions, plus `/privacy` and `/help` pages. `/privacy` can also be the App Store privacy policy link. |

---

# Hosting at gregular.tv

Use **Cloudflare Workers with static assets**. For a site with no server code it's free, and it lets us set the security headers. Cloudflare now recommends it over Pages for new projects. GitHub Pages can't set headers, so it isn't suitable.

Steps marked **(you)** need the owner's accounts, payment or tokens. **(Claude)** steps are code in this repo.

1. **(you) Register the domain.** Check whether gregular.tv is available at Cloudflare Registrar, which sells .tv at cost for about $25 a year and keeps the owner's details private. If it's taken or listed as a premium name, the price differs.
   - If it's bought elsewhere, add it to a free Cloudflare account and change the nameservers at that registrar.
2. **(you) Turn on DNSSEC** under DNS › Settings. It's automatic if the domain was bought at Cloudflare.
3. **(you) Block email spoofing.** The domain won't send email, so add these DNS records, which stop anyone sending mail as gregular.tv:
   - `MX gregular.tv 0 .`
   - `TXT gregular.tv "v=spf1 -all"`
   - `TXT _dmarc.gregular.tv "v=DMARC1; p=reject; sp=reject; adkim=s; aspf=s"`
4. **(you) Let GitHub deploy.**
   - Create a Cloudflare API token from the "Edit Cloudflare Workers" template, limited to the account.
   - In the GitHub repo, add two secrets: `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID`.
5. **(Claude, in phase 5) Deployment files.**
   - A `wrangler.jsonc` with `assets: { directory: "Web/dist", not_found_handling: "single-page-application" }`, no worker script, and observability off.
   - A GitHub Actions workflow that runs on every push to main. It installs the swift.org toolchain and the WebAssembly SDK, builds the site, runs the tests and runs `npx wrangler deploy`.
   - Pull requests get preview addresses.
6. **(you) Connect the domain.**
   - In Workers & Pages › gregular-tv › Settings › Domains & Routes, add `gregular.tv` and `www.gregular.tv`.
   - Under Rules, add a 301 redirect from `www.gregular.tv/*` to `https://gregular.tv/${1}`.
7. **(you) Set up HTTPS** under SSL/TLS:
   - Always Use HTTPS on, minimum TLS 1.2, TLS 1.3 on.
   - Turn on HSTS with a 6-month max-age.
   - After a few weeks with no problems, raise it to 2 years with includeSubDomains, and optionally submit the domain to hstspreload.org.
8. **(you) Turn off anything that injects scripts or collects visitor data:**
   - Web Analytics / Browser Insights, Rocket Loader, Email Address Obfuscation, Zaraz and Bot Fight Mode.
   - These would break the Content Security Policy and the privacy promise.
   - Cloudflare will still see the IP address of people downloading the app's files; `/privacy` says so. It never sees Jellyfin traffic.
9. **(Claude) Caching** through `_headers`:
   - Every file is checked on each visit (`Cache-Control: no-cache`): the build's file names don't change between versions, so a browser revalidates (a quick 304) rather than keeping an old app.
   - Brotli compression and the WebAssembly file type (`application/wasm`) are set automatically.
10. **Check it.**
    - `curl -I https://gregular.tv` shows the headers.
    - Mozilla Observatory should give A+.
    - Sign in to a real https Jellyfin server in Safari, Firefox and Chrome, and to an http LAN server in Chrome.

**Cost:** the domain is about $25 a year; hosting is free.

## Decisions taken

1. **Http servers:** https in every browser, http on the home network in Chrome and Edge only. (A copy people serve on their own network stays a possible later phase.)
2. **Views in Swift**, with a small view layer of our own (`Web/Sources/GregularWeb/Support`: elements, observation-driven redraws, focus), not ElementaryUI or TypeScript.
3. **Cloudflare** Workers static assets (`Web/wrangler.jsonc`, `.github/workflows/web.yml`).
4. **Design:** mobile first. On a phone held upright, the picture at the top, what's on and the controls under it, every channel's now and next below; landscape and larger screens get the full picture with a card over it, and side sheets. One set of design tokens (`Web/public/app.css`), SVG icons, WCAG AA contrast, 44 px touch targets, labelled controls, switches and radios with their states, inert content under open panels, and the reader's text size, motion, contrast and transparency settings respected.

## What building it found

- **WebAssembly's `Int` is 32 bits.** Two places overflowed: the speed test on a fast connection (now capped at 2 Gbps) and the schedule's commercial estimate with no commercials (now zero). The package's own tests now run under WebAssembly (`scripts/test-web.sh unit`) to catch the next one: all 196 Core, 44 Jellyfin and 42 Screens tests pass there (4 Screens tests that wait fractions of a second are skipped: the interpreter is too slow for them; they run natively).
- **The stack.** WebAssembly has no tail calls, so an `await` that finishes without suspending stays on the stack; with the linker's small default stack, a loop of them overflowed. The app and the test runners get an 8 MB stack.
- **URLSession's types** (`URLRequest`, `HTTPURLResponse`) don't exist in the browser, so `HTTPTransport` uses the app's own `ServerRequest` and `ServerReply`.
- **Download size:** 45 MB, 12.4 MB brotli-compressed (the plan hoped for under 10). Most of it is the ICU data Foundation needs for time zones and date formatting; the schedule needs real time zones. Visits after the first only revalidate the files. Cloudflare serves no file over 25 MiB, so the build splits the app into parts (named for the build, listed in `app/wasm.json`), which `js/main.js` joins as they download; the build fails if any file is still too large.
- **Joining live:** a browser can say it's ready at the start of a file before it seeks to the live position, or deliver the file's details after that seek. Either made the player think it was an hour behind live and re-tune, with a speed test, every second. `VideoDeck` now reports where a seek is going until it lands, as `AVPlayer` does, and sets the starting point before loading. The walkthrough checks no speed test runs while playing normally.
- **The demo video** had a frame every ten minutes, which browsers stall on (Apple TV doesn't): it has one every two seconds now, and the demo server sends open-ended ranges a megabyte at a time, as media servers do.
- **Browsers:** a browser can't play a file over http from an https page, so from an http server everything comes as HLS. Firefox occasionally never starts loading a file (no error), so a file with no data after 8 s is asked for again. Browsers start video silently until the viewer interacts, so the app says "Tap for sound".
- **Still to try on real servers:** an https Jellyfin server in each browser, and an http LAN server in Chrome (the local network permission prompt, and HLS through hls.js).

## Sources

- [Getting Started with Swift SDKs for WebAssembly](https://www.swift.org/documentation/articles/wasm-getting-started.html)
- [JavaScriptKit](https://swiftpackageregistry.com/swiftwasm/JavaScriptKit)
- [Chrome: Local Network Access permission](https://developer.chrome.com/blog/local-network-access)
- [MDN: Request.targetAddressSpace](https://developer.mozilla.org/en-US/docs/Web/API/Request/targetAddressSpace)
- [Cloudflare: Migrate from Pages to Workers](https://developers.cloudflare.com/workers/static-assets/migration-guides/migrate-from-pages/)
- [Cloudflare Workers: static asset headers](https://developers.cloudflare.com/workers/static-assets/headers/)
- [Cloudflare Registrar TLDs](https://domains.cloudflare.com/tlds)
