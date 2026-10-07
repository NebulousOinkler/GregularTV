# Audit: security, privacy and open risks

An audit of the whole codebase on 2026-10-07 (main at 233185c), to be worked through later. Nothing here is fixed yet unless it says so. Each finding says where it is, what could go wrong, and a suggested fix. Severity is for this app as it's used: one household's own Jellyfin server, an Apple TV, and gregular.tv.

What was checked: every request path (`JellyfinAPI`, `URLSessionTransport`, `FetchTransport`, `WholeFile`, the players), sign-in storage (`KeychainStore`, `BrowserCredentialStore`, `vault.js`), the pages the Apple TV serves on the home network (`LocalPageServer`, `HTTPRequest`, `LocalPage`, `EditingAPI`, `SongPickerAPI` and their scripts), codes and documents typed or pasted in (`CodeReader`, `CustomChannel`, `SetTimes`, `EditingDocument`), the web version's headers and scripts, the CI workflow and hosting config, the dependencies, the privacy and layer checks, and the repository's history.

What held up well: plain http only on the home network, enforced in shared code for every request; redirects only on the same server; replies capped in size; no disk caches, cookies or logs; sign-ins in the Keychain (this device only) or encrypted in the browser; a random device ID per sign-in; no playback reporting; the local pages' code, address, origin and rate checks; codes and documents validated before use; a strict Content Security Policy with Trusted Types; no `innerHTML` anywhere; and vendored, pinned libraries.

## High

### H1. A special mode's keyword is still public in the repository's history
- **Where:** GitHub keeps `refs/pull/54/head` for good, and the repository is public. That ref still reaches commit a2ebcff and the commits before it, whose files hold the keyword in plain text (from before it was replaced by its hash). Deleting the `special-mode` branch didn't remove them.
- **Risk:** anyone can read the keyword, so the special mode isn't secret. It gives no access to anything, so it's a secrecy problem, not a security hole.
- **Fix:** pick a new keyword, put its hash in `special-modes.jsonc` (`swift run keyword-hash`), and update the walkthroughs' `SPECIAL_MODE_KEYWORD`. Or ask GitHub Support to remove the pull request's ref and cached views. Rotating the keyword is the reliable fix.

## Medium

### M1. The deploy step runs an unpinned tool with the Cloudflare token
- **Where:** `.github/workflows/web.yml`, `npx --yes wrangler@4 deploy`.
- **Risk:** it runs whatever `wrangler` 4.x is newest at deploy time, with `CLOUDFLARE_API_TOKEN` in its environment. A bad release could take the token and publish its own site at gregular.tv. That site could then read every visitor's saved sign-ins, since they're decrypted in the page.
- **Fix:**
  - Add `wrangler` to `Web/package.json` at an exact version, so `npm ci` installs it from the lockfile, and run `npx wrangler deploy` from there.
  - Limit the token to editing this one Worker.

### M2. CI tools that build the site aren't checked
- **Where:** `web.yml`.
  - `swiftly.pkg` is downloaded and installed with no checksum or signature check. Only the WebAssembly SDK is checksummed.
  - `brew install binaryen` installs whatever version is current.
  - `actions/checkout@v4` is pinned to a tag, not a commit.
- **Risk:** a compromised tool could change the site that's deployed.
- **Fix:**
  - Pin actions to commit SHAs.
  - Check the pkg with `pkgutil --check-signature` (or a checksum).
  - Pin binaryen's version.
  - Build in a job with no secrets, and deploy its output from a separate job that only deploys.

### M3. The browser vault protects less than its comments say
- **Where:** `Web/public/js/vault.js`, README *The web version*.
- **Risk:** the comment says a copy of the browser's files doesn't give the sign-ins away. But browsers save a non-extractable CryptoKey in the same profile as the data it encrypts. Anyone with the profile's files can still decrypt the sign-ins, such as malware, a backup, or another person on a shared computer account. Jellyfin tokens don't expire until they're revoked.
- **Fix:**
  - Correct the comment and the README.
  - Offer "don't remember me on this browser", which keeps the sign-in in memory only.
  - Point shared-computer users to *Forget everything*.

### M4. Access tokens go in stream URLs
- **Where:** `JellyfinClient.directPlayURL` adds `ApiKey=`, and Jellyfin's own `TranscodingUrl` carries the token too. This covers direct play, HLS and whole song files.
- **Risk:** the token is a full account sign-in that doesn't expire. It lands in Jellyfin's access logs, any reverse proxy's logs, and the players' own request handling (AVFoundation, VLC, hls.js). In a browser, extensions and the network panel can see it. Every Jellyfin client works this way.
- **Fix:**
  - Keep recommending a non-administrator account; the app already warns about administrator accounts.
  - Tell users that proxy logs hold the token.
  - Check whether newer Jellyfin versions offer a token limited to streaming.

### M5. The VLC fallback is a large parser of untrusted files
- **Where:** `VLCItem` and the SwiftVLC 1.0.0 dependency. SwiftVLC is a small third-party wrapper that ships libVLC as a binary.
- **Risk:**
  - The fallback plays exactly the files Apple's player can't: the rarest, least-tested formats. libVLC has a long history of demuxer vulnerabilities, so a malicious or damaged file in the library could attack the app.
  - VLC makes its own requests, with its own TLS stack and User-Agent. Nothing tests that it rejects an untrusted certificate.
  - The privacy check can't see whether it writes caches or logs.
- **Fix:**
  - Test VLC against a self-signed https server; it must refuse.
  - Keep SwiftVLC current and follow libVLC advisories.
  - Consider a Settings switch to turn the fallback off.

## Low

### L1. Media the browser fetches itself skips the transport's rules
- **Where:** `VideoSlot.load` sets `<video>.src` for direct play, and for HLS where hls.js isn't supported (Safari on older iPhones).
- **Risk:** these are no-cors requests, unlike the app's own requests and hls.js's:
  - they send any cookies the browser holds for the server, such as a single-sign-on proxy's;
  - they follow redirects anywhere;
  - they aren't marked `targetAddressSpace`.
- **Fix:**
  - Set `crossOrigin = "anonymous"` on the video elements so no credentials are sent; Jellyfin answers CORS for media.
  - Document that redirects can't be controlled.

### L2. The web version's song download skips the server checks
- **Where:** `SongPlayer.load` calls `WholeFile.fetch` directly. On Apple TV, the same download goes through `JellyfinClient.download`, which applies `ServerAddress.isAllowed` and `isOnThisServer`.
- **Risk:** small, since the URL comes from the server's own playback info. But the two platforms enforce different rules.
- **Fix:** give the web version the same path (`OriginalFiles.download`), or make the check public in GregularJellyfin and call it from `WholeFile`.

### L3. Single-word server names count as the home network
- **Where:** `ServerAddress.isOnLocalNetwork`.
- **Risk:** a name like `jellyfin` can resolve through a DNS search domain to a host outside the home, for example on an office or ISP network. Plain http, with a password, would then be allowed.
- **Fix:** for plain http, accept only `.local`, `.home.arpa`, `localhost` and private addresses, or warn when a single-word name is used over http.

### L4. An upgrade redirect may change the port
- **Where:** `TransportRules.allowsRedirect`.
- **Risk:** a redirect from `http://host:8096` may go to `https://host` on any port. It's the same host, so this is small.
- **Fix:** allow only port 443, or the same port.

### L5. The browser may offer to save the Jellyfin password
- **Where:** `LoginPage` gives the password field `autocomplete="current-password"`.
- **Risk:** the browser's password manager may save the password under gregular.tv. That's the viewer's choice, but it doesn't match "the password is never stored".
- **Fix:** decide which you want, then change the field or the README.

### L6. The site is also served at the workers.dev address
- **Where:** `Web/wrangler.jsonc` has `workers_dev: true` and `preview_urls: true`.
- **Risk:**
  - The site also lives at `gregular-tv.<account>.workers.dev`. That's a second origin with its own storage, and the account's subdomain may identify its owner.
  - Preview URLs can keep old versions reachable. CI no longer uploads previews.
- **Fix:** set both to false now that gregular.tv is live.

### L7. gregular.tv doesn't send HSTS
- **Where:** `Web/public/_headers`.
- **Risk:** without `Strict-Transport-Security`, a first visit typed as `gregular.tv` could be intercepted before the redirect to https, unless HSTS is turned on in Cloudflare.
- **Fix:** add `Strict-Transport-Security: max-age=31536000; includeSubDomains`, or turn it on in Cloudflare.

### L8. The Content Security Policy must allow connections to any server
- **Where:** `_headers` has `connect-src` and `media-src https: http:`.
- **Risk:** this is needed, because the server is the viewer's choice. But any script injection could then send sign-ins anywhere. Trusted Types, and only ever writing text into the page, are the defence.
- **Fix:** make `scripts/privacy-check.sh` (or the layer check) fail on `innerHTML`, `outerHTML`, `insertAdjacentHTML`, `eval` and `new Function` in the app's own code. There are none today.

### L9. The privacy check doesn't scan the pages served on the home network
- **Where:** `scripts/privacy-check.sh` scans `Web/public/js` for browser storage and console logging, but not `Sources/GregularScreens/**/*.js` (`local-page.js`, `editor.js`, `picker.js`).
- **Risk:** none today, since those scripts are clean, but a future change wouldn't be caught.
- **Fix:** add `Sources` with `--include='*.js'` to the web scan.

### L10. The local pages are plain http
- **Where:** `LocalPageServer`.
- **Risk:**
  - Anyone sniffing the Wi-Fi can read the six-digit code, the library names and the queue, and use the code while the page is open. The TV says so.
  - Only private IPv4, link-local and unique-local IPv6 addresses are accepted. Most home IPv6 addresses are global, so in practice the pages work over IPv4 only.
- **Fix:** nothing needed beyond the on-screen warning. Note the IPv4-only behaviour if someone reports the page as unreachable.

### L11. Custom channels are only fully checked on the editing page
- **Where:** `EditingDocument.ChannelEntry.channel()` checks a channel's name (not empty, at most `CustomChannel.longestName`), its condition count and its years. `CustomChannel(code:)` and `ChannelLineup.adding` don't.
- **Risk:** a name of up to 255 bytes, or an empty one, from a stored or hand-made code would be accepted.
- **Fix:** keep the checks with `CustomChannel` in GregularCore and apply them on every route. **Fixed on this branch** (`CustomChannel.problems`).

### L12. Item IDs from the server go into request paths unescaped
- **Where:** for example `"/Items/\(itemID)/PlaybackInfo"`, and `JellyfinAPI.url` force-unwraps the URL it builds.
- **Risk:** a hostile server could only make the app call its own endpoints. An odd ID might crash the app, though, especially on WebAssembly Foundation.
- **Fix:** percent-encode IDs as one path segment, and make `url(_:query:)` throw instead of force-unwrapping.

### L13. Keyword hashes can be checked against a dictionary
- **Where:** `SpecialModeRegistry` stores an unsalted SHA-256 of a short word.
- **Risk:** it hides the keyword from casual readers only; anyone can test a word list against it. Special modes give no access to anything, so this is acceptable.
- **Fix:** none needed. Don't use the keyword mechanism for anything that needs to be secret.

### L14. The shared Xcode project names one developer's team
- **Where:** `project.pbxproj` sets `DEVELOPMENT_TEAM`.
- **Risk:** the Team ID isn't a secret, but it identifies the developer account, and every fork has to change it anyway.
- **Fix:** move signing settings to an xcconfig that git ignores, if that matters to you.

### L15. Two copies of the local-address check disagreed
- **Where:** `ServerAddress.isOnLocalNetwork` and `LocalPage.isLocal`.
- **Risk:** `isOnLocalNetwork` matched IPv6 by text prefix, so a shortened address such as `fc1::1` (really `0fc1::1`) counted as local.
- **Fix:** **Fixed on this branch.** Both now use one parser, `LocalNetwork.contains(address:)` in GregularCore.

## Other open risks

1. **Not yet checked on real hardware** (TODO.md, items 1 to 6):
   - buffering with the real server's diagnostics;
   - a "Buffering…" banner that may not clear;
   - the main page and the editing page on a real Apple TV, including tvOS's local-network permission;
   - the web version against real servers in each browser.
2. **Every push to main goes live:**
   - There's no staging step. A broken build reaches every visitor within about 17 minutes, and the only rollback is in the Cloudflare dashboard (used on 2026-10-07).
   - **Fix:** require approval for the deploy (a GitHub environment), or deploy to a preview first.
3. **Company networks can block the web version:**
   - Company proxies, such as the Palo Alto proxy seen on 2026-10-07, can turn away cross-origin requests to the viewer's server, and nothing in the app can fix that.
   - The error message could mention proxies and VPNs.
4. **Jellyfin behaviour the app relies on:**
   - It depends on details that aren't part of Jellyfin's documented contract: `subtitleStreamIndex=-1` needs `mediaSourceId`, `/Sessions/Playing/Ping` keeps a transcode going, and a transcode stops a minute after its last request.
   - A Jellyfin update could change any of them unnoticed.
   - **Fix:** a check against a real Jellyfin version in CI, or a note in the release checklist.
5. **Schedule seams:** a programme can repeat or be skipped where one day's run meets the next (about 1,067 times in 30 days in the schedule audit). This is accepted.
6. **Web download size:** 12.4 MB compressed, mostly Foundation's ICU data. The first load is slow on a phone.
7. **Tests that occasionally fail:**
   - One walkthrough page load hung once and passed when run again.
   - The app tests depend on simulator DNS timing; this was fixed in 7b8652d.
8. **Out-of-date document:** COMPARISON.md still says Gregular TV only plays on an Apple TV, from before the web version.
