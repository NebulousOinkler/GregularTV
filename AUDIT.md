# Audit: security, privacy and open risks

An audit of the whole codebase on 2026-10-07 (main at 233185c). Each finding says where it was, what could go wrong, and what was done: **resolved** (changed, and tested where it can be) or **accepted** (left as it is, and why). Severity is for this app as it's used: one household's own Jellyfin server, an Apple TV, and gregular.tv.

What was checked:
- every request path (`JellyfinAPI`, `URLSessionTransport`, `FetchTransport`, `WholeFile`, the players);
- sign-in storage (`KeychainStore`, `BrowserCredentialStore`, `vault.js`);
- the pages the Apple TV serves on the home network (`LocalPageServer`, `HTTPRequest`, `LocalPage`, `EditingAPI`, `SongPickerAPI` and their scripts);
- codes and documents typed or pasted in (`CodeReader`, `CustomChannel`, `SetTimes`, `EditingDocument`);
- the web version's headers and scripts;
- the CI workflow and hosting config;
- the dependencies;
- the privacy and layer checks;
- the repository's history.

What held up well:
- **Requests:**
  - plain http only on the home network, enforced in shared code for every request;
  - redirects only on the same server;
  - replies capped in size.
- **Storage:**
  - no disk caches, cookies or logs;
  - sign-ins in the Keychain (this device only) or encrypted in the browser.
- **What the server learns:** a random device ID per sign-in, and no playback reporting.
- **Local pages:** the code, address, origin and rate checks.
- **Input:** codes and documents are validated before use.
- **Web:**
  - a strict Content Security Policy with Trusted Types;
  - no `innerHTML` anywhere;
  - vendored, pinned libraries.

## High

### H1. A special mode's keyword is still in the repository's history — accepted
- **Where:** GitHub keeps `refs/pull/54/head` for good, and the repository is public. That ref reaches commits from before the keyword was replaced by its hash.
- **Accepted:** the keyword only opens a special mode and gives no access to anything. Keeping it secret isn't important (decided 2026-10-07). The hashes in `special-modes.jsonc` stay as they are.

## Medium

### M1. The deploy step ran an unpinned tool with the Cloudflare token — resolved
- **Where:** `.github/workflows/web.yml` ran `npx --yes wrangler@4 deploy`, which fetched whatever Wrangler 4.x was newest, with `CLOUDFLARE_API_TOKEN` in its environment.
- **Resolved:**
  - Wrangler is an exact dev dependency (`Web/package.json`, 4.136.3), installed from `Web/package-lock.json` by `npm ci`, and run with `npx --no-install`.
  - Wrangler's usage reports are off (`WRANGLER_SEND_METRICS=false`).
  - WEB_PLAN.md says to limit the token to the account and the gregular.tv zone.

### M2. CI tools that build the site weren't checked — resolved
- **Where:** `web.yml` installed `swiftly.pkg` and binaryen unchecked, and used actions by tag.
- **Resolved:**
  - Actions are pinned to commit SHAs, and checkouts don't keep their token.
  - The swiftly installer must be notarized and signed "Developer ID Installer: Swift Open Source (V9AUD2URP3)".
  - binaryen is a pinned release with its SHA-256 checked.
  - The site is built in a `build` job that has no secrets. A separate `deploy` job only publishes `build`'s output, so no build tool ever sees the token.
  - The `deploy` job runs in a `gregular.tv` environment, which can require approval (see Other open risks, item 2).

### M3. The browser vault protected less than its comments said — resolved
- **Where:** `Web/public/js/vault.js`, README *Privacy*.
- **Risk:** browsers keep the non-extractable key in the same profile as the data it encrypts. Anyone with the profile's files can decrypt the sign-ins, and Jellyfin tokens don't expire until revoked.
- **Resolved:**
  - The comment and the README now say what the encryption does and doesn't do.
  - Sign-in has a **Remember me on this browser** switch. Turned off, the sign-in is kept in memory for that visit only and never written to the browser (`BrowserCredentialStore.rememberNextSignIn`).
  - The walkthrough checks that such a sign-in is gone after a reload.

### M4. Access tokens go in stream URLs — accepted, with mitigations
- **Where:** `JellyfinClient.directPlayURL` adds `ApiKey=`, and Jellyfin's own `TranscodingUrl` carries the token too.
- **Accepted:** a player can't attach a header to every request it makes, and Jellyfin's own HLS playlists carry the token. Every Jellyfin client works this way.
- **Mitigations:**
  - The app asks before signing in with an administrator account.
  - Diagnostics and errors never show a URL (`FriendlyError`).
  - Signing out revokes the token.
  - The README now says plainly that logs hold the token: keep them private, and sign out or remove the device to cancel it.

### M5. The VLC fallback parsed almost any file — resolved
- **Where:** `VLCItem`, `PlayableFormats.vlcOnAppleTV`, SwiftVLC 1.0.0 (exact version, pinned revision).
- **Resolved:**
  - VLC is offered only common containers (MKV, WebM, AVI, MPEG-TS, MP4/MOV, WMV/ASF, MPEG, VOB, FLV, Ogg, 3GP) and the codecs a video library really holds. The rarest readers (H.261, H.263, Dirac, FLV1, MS-MPEG4 v1/v2, Nellymoser, Speex, AMR, WavPack) are dropped, so those files are converted by the server instead.
  - SwiftVLC's libVLC has no Lua, which was checked in the binary, so it runs no scripts on what it reads.
  - A test (`VLCSetupTests`) checks libVLC accepts the app's arguments (`--quiet`). Without that, it would silently start with its defaults, which log. The test caught that `--no-lua` isn't an option in this build.
  - **Certificates:** libVLC's TLS is its SecureTransport module, so certificates are checked against Apple's trust store. The app gives libVLC no dialog handler, so where VLC would ask "Accept certificate temporarily", the answer is no and the stream fails. This is documented in `VLCItem`.
  - Keeping SwiftVLC current stays a maintenance task.

## Low

### L1. Media the browser fetched itself sent cookies — resolved
- **Where:** `VideoSlot`'s `<video>` loaded direct-play files, and HLS where hls.js isn't supported, as no-cors requests that send cookies.
- **Resolved:**
  - Video elements are `crossorigin="anonymous"`, so no cookies or credentials go with them. Jellyfin answers CORS for media.
  - Redirects of the browser's own media requests can't be controlled from a page; the README says so.

### L2. The web version's song download skipped the server checks — resolved
- **Where:** `SongPlayer.load` called `WholeFile.fetch` directly.
- **Resolved:**
  - `OriginalFiles.checkDownload` runs the same check as `JellyfinClient.download`: an allowed server, and the file on it.
  - The web's `SongPlayer` calls it, through `SpecialModeSession.checkFile`, before fetching.
  - It's tested in `SpecialLibraryTests`.

### L3. Single-word server names counted as the home network — resolved
- **Where:** `ServerAddress.isOnLocalNetwork`.
- **Resolved:**
  - Plain http now goes only to `localhost`, `.local` and `.home.arpa` names, and to private addresses. A one-word name such as `nas` needs https, its IP address or `nas.local`, and the error message says so.
  - This changes behaviour: a server added as `http://nas:8096` must be added again as `http://nas.local:8096` or by its address.

### L4. An upgrade redirect could change the port — resolved
- **Where:** `TransportRules.allowsRedirect`.
- **Resolved:** a redirect from http to https on the same host may go only to port 443 or Jellyfin's 8920 (`upgradePorts`). This is tested.

### L5. The browser may offer to save the Jellyfin password — resolved
- **Where:** `LoginPage`'s password field is `autocomplete="current-password"`.
- **Resolved:** kept, so password managers and accessibility tools work. The README now says the browser may offer to save it, which is the viewer's choice, and that the app never stores it.

### L6. The site was also served at the workers.dev address — resolved
- **Where:** `Web/wrangler.jsonc`.
- **Resolved:**
  - `workers_dev` and `preview_urls` are off.
  - gregular.tv is declared as the Worker's custom domain in the file, so the file, not the dashboard, says where the site is. www.gregular.tv stays a DNS record of its own with a redirect rule. Declaring it too failed the first deploy (2026-10-07: Cloudflare won't make a custom domain where a DNS record exists).

### L7. gregular.tv didn't send HSTS itself — resolved
- **Where:** `Web/public/_headers`.
- **Resolved:** the site sends `Strict-Transport-Security: max-age=31536000`, whether or not HSTS is also on in Cloudflare (WEB_PLAN.md step 7). `includeSubDomains` is left out so no other subdomain is forced to https.

### L8. Nothing stopped code that sets HTML — resolved
- **Where:** `_headers` must allow `connect-src` and `media-src` to any server (the viewer's choice), so a script injection could send sign-ins anywhere.
- **Resolved:** `scripts/privacy-check.sh` fails on any code that sets HTML or runs text as script: `innerHTML`, `outerHTML`, `insertAdjacentHTML`, `document.write`, `eval(`, `new Function`, `setHTMLUnsafe` and `createContextualFragment`. It covers the app's Swift, JavaScript and HTML everywhere. It runs in the app's build, in `swift test` and in CI.

### L9. The privacy check skipped the home-network pages — resolved
- **Where:** `scripts/privacy-check.sh`.
- **Resolved:** the browser-storage and logging scan now covers `Sources/**/*.js` too (`local-page.js`, `editor.js`, `picker.js`). A test edit confirmed it catches one.

### L10. The local pages are plain http — accepted
- **Where:** `LocalPageServer`.
- **Accepted:** a browser can't trust a certificate from a TV. The page is off by default, only on while its screen is open, protected by a one-time code and the address, origin and rate checks, and the TV says to use it on a trusted network.
- **IPv6:** the earlier worry about global IPv6 addresses doesn't apply. The TV only shows its IPv4 address, so phones always connect over IPv4.

### L11. Custom channels were only fully checked on the editing page — resolved
- **Resolved:** `CustomChannel.problems` and the `CustomChannelsMakeSense` rule in GregularCore check every channel however it arrives. This is tested.

### L12. Item IDs from the server went into request paths unescaped — resolved
- **Where:** for example `"/Items/\(itemID)/PlaybackInfo"`.
- **Resolved:**
  - IDs and containers go into paths through `JellyfinAPI.segment(_:)`, which escapes everything but letters, digits, `-` and `_`. A slash, dot, `?` or `#` can't reach another path or break the URL.
  - `url(_:query:)` builds from escaped parts, so its URL always exists.
  - This is tested (`anOddItemIDStaysInItsPlace`).

### L13. Keyword hashes can be checked against a dictionary — accepted
- **Accepted:** special modes give no access to anything (see H1).

### L14. The shared Xcode project named one developer's team — resolved
- **Where:** `project.pbxproj` set `DEVELOPMENT_TEAM`.
- **Resolved:**
  - The app's configurations read `App/Signing.xcconfig`, which includes `App/Signing.local.xcconfig` if it exists. Git ignores the local file, and each developer puts their team there; the README says how.
  - The Team ID is still in the history, which is fine: it isn't a secret.

### L15. Two copies of the local-address check disagreed — resolved
- **Where:** `ServerAddress.isOnLocalNetwork` and `LocalPage.isLocal`.
- **Resolved:** both use one parser, `LocalNetwork.contains(address:)` in GregularCore. The text-prefix bug (`fc1::1` counted as local) is gone, and this is tested.

## Other open risks

1. **Not yet checked on real hardware** (TODO.md, items 1 to 6): playback on the real server, the main page and the editing page on an Apple TV, and the web version in each browser.
   - **Open:** these need a person with the devices.
2. **Every push to main went live — resolved, needs one setting:**
   - The deploy runs in the `gregular.tv` environment. Adding yourself as its required reviewer (GitHub › Settings › Environments, see WEB_PLAN.md) makes each deploy wait for approval.
   - Until then, deploys stay automatic. Cloudflare's dashboard can still roll back.
3. **Company networks can block the web version — resolved as far as the app can:**
   - A proxy can turn away cross-origin requests to the viewer's server.
   - The "Couldn't reach your server" message now says a work or school network, or a VPN, may be blocking it.
4. **Jellyfin behaviour the app relies on — resolved:**
   - README *Debug options* lists each behaviour that Jellyfin doesn't promise, and how to check it after an upgrade.
   - TODO.md item 7 reminds to.
5. **Schedule seams — accepted:** a programme can repeat or be skipped where one day's run meets the next (decided 2026-10-07: the seams aren't the problem).
6. **Web download size — open:** 12.4 MB compressed (TODO.md item 6). It waits on the Swift WebAssembly SDK.
7. **Tests that occasionally fail — resolved or not reproduced:**
   - The app tests' DNS timing was fixed in 7b8652d.
   - The one walkthrough page load that hung hasn't happened again.
8. **Out-of-date documents — resolved:** COMPARISON.md and PLAN.md's web paragraph are up to date.
