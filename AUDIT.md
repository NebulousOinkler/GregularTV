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

## Third audit: 2026-10-26 (the rest of the quality plan, and the iPhone fix)

The whole codebase again, before the rest of the quality plan ships with the fix for iPhones:
- the iPhone fix (a video the browser couldn't fetch was taken for one it couldn't decode);
- Remember me off by default;
- choosing a sound track;
- converting songs;
- the speed test limited by time;
- converted next programmes 90 s ahead;
- the heaviest re-encodes' head start;
- the clean-up tasks C3 to C6.

**Scope.** Changed since the second audit: 42 files, about 1,100 lines, in playback, the web's sign-in page and player, and tests. Unchanged since it, and so as it found them:
- the request gateway and its rules (`JellyfinAPI`, the transports: one comment in `HTTPTransport` aside);
- the browser's fetch rules and `WholeFile`;
- sign-in storage (`KeychainStore`, `vault.js`);
- the editing and song pages;
- `_headers`;
- CI, the dependencies and their lockfiles;
- the privacy and layer checks.

Both checks pass.

### Q1. The second audit's P5 said a misreported decode failure never stops a file playing; it did — resolved
- **Where:** `VideoDeck` (the `error` event), `ChannelPlayer.fail`.
- **Risk:**
  - Before anything loads, a browser reports a video it couldn't fetch at all (a refused connection, a missing file) with the same error as one it can't decode: `MEDIA_ERR_SRC_NOT_SUPPORTED`. The HTML standard says so, and it was checked in Chromium.
  - Every such failure was taken as the format's. A stream in the safest formats (H.264 and AAC), which every iPhone stream is, had nothing to rule out, so it said "This programme can't be played on this device" at once, for the rest of its slot.
  - Elsewhere, a network blip ruled out a format the browser plays.
  - P5 accepted this risk on the grounds that it "never stops a file playing", which was wrong.
- **Resolved:**
  - The web deck now fetches the stream's first byte when a video fails before loading (`reach` in `hls-player.js`): sent, it's the format's; refused, the server's; no answer, the connection's.
  - A "can't decode" on a stream in only the safest formats is retried twice, as any failure, before it says it can't play (`ChannelPlayer.safestFormatRetries`).
  - Tests: a walkthrough test refuses the first stream requests, and fails on the old code in Chromium, WebKit and Firefox. `UnplayableTests.theRetriesEndAndSaySo` covers the retries.
  - P5 stands for VLC's and hls.js's media errors, which aren't the browser's own.

### Q2. The web kept sign-ins unless told not to — resolved
- **Where:** the sign-in page's *Remember me on this browser* (`LoginPage`).
- **Risk:** a remembered sign-in is encrypted, but readable by anyone with the browser profile's files (M3), and it was kept unless the viewer thought to turn the switch off.
- **Resolved** (the user's decision, 2026-10-26): keeping it is opt-in. The switch starts off; README and M3 say so. The walkthrough checks it starts off, and that a sign-in not remembered is gone after a reload.

### Q3. The new first-byte check sends a request from the page — reviewed, nothing to change
- **Where:** `reach` in `hls-player.js`, called by `VideoDeck` only after a video fails before loading.
- **What it sends:** a request for the first byte of the stream's own URL, which is always on the user's own server (made by `JellyfinClient`, or Jellyfin's `TranscodingUrl` made absolute on the same server). It sends:
  - the same `ApiKey` the video's own request did (M4);
  - no cookies, no referrer, no cache;
  - no redirect followed;
  - a request marked as home-network for plain http, as hls.js's are.

  It gives up after 10 seconds.
- **No new exposure:** the server already got the same URL from the video itself, and nothing goes anywhere else.

### Q4. More is read about a programme's sound tracks, and one more request is made — resolved, in the docs
- **Where:** `MediaSource.soundTrackToCopy(into:)`, `JellyfinClient.withASoundTrackToCopy`.
- **What changed:**
  - To choose a sound track the device plays as it is, the app reads each track's channels, language and name from the `PlaybackInfo` answer it already gets. They stay in memory, and the name is used only to skip commentaries.
  - Where that spares a conversion, it asks `PlaybackInfo` once more, naming the track.
- **Resolved:** README *Privacy* and PLAN §3 say so. The extra request goes to the user's own server, and only for such a file.

### Q5. Songs a device doesn't play are now converted by the server — reviewed
- **Where:** `JellyfinClient.wholeFileURL(of:)`, `DeviceProfile.TranscodingProfile.song`.
- **What changed:** a song is no longer skipped; Jellyfin converts its sound into one AAC file as it's fetched.
- **Why it's safe:**
  - Its URL is Jellyfin's `TranscodingUrl`, made absolute on the same server.
  - It's fetched as before, through `WholeFiles.download` or `checkDownload`: on that server only, capped in size as it arrives.
  - A conversion that's a stream (`.m3u8`) is refused, not fetched.
- **The cost to the server:** one sound conversion at a time, plus the next song's, as it's loaded ahead.

### P4, confirmed
The updated GitHub Actions passed their first run on a pull request (#69: build and deploy rehearsal), and then the deploy to gregular.tv from main.

### The clean-up pass
- **Coupling:** none; the layer check passes.
- **One place each:**
  - the player's waits that tests change (`ChannelPlayer.Timings`, instead of shared values two Apple TV suites left changed);
  - the player's words (`PlayerText`; decks report a `DeckActivity`, not their own words);
  - the order players are asked about (`MediaStream.Player.order`);
  - the fake server's behaviour (`FakeStreams.Treatment`).
- **Renamed for what it does:** `OriginalFiles` became `WholeFiles`, as a song's file may now be a conversion; `afterBreak` became `standbyProgramme`.
- **Out of the repository:** the uncommitted quality map, folded into PLAN §7a.

### Not checked
- Real hardware and a real server (PLAN §7a, *Still open*).
- The karaoke walkthroughs, which need the keyword.

## Second audit: 2026-10-25 (the playback rework)

The whole codebase again, before the playback rework (Auto per programme, programme settings, error kinds, delivery kinds, the sound ladder, ladders for the web, ruling out formats a player can't decode, the browser's format checks) ships. Changed since the first audit: 44 files, about 1,800 lines, almost all in playback. Unchanged since it, and so as it found them: the request gateway and its rules, sign-in storage, the local pages, the web headers and scripts, CI, the hosting config and the dependencies (hls.js 1.7.3, SwiftVLC 1.0.0, Wrangler 4.136.3). The privacy and layer checks pass; nothing in the changes or their commit messages names an address, token or password.

### P1. A server could keep the decode-failure retries going — resolved
- **Where:** `UnplayableFormats`, `ChannelPlayer.fail`.
- **Risk:** after a decode failure the app rules out a format the stream carried and asks again at once, with no wait. "It always ends" rested on the server describing each file the same way each time. A misbehaving server that named a different format on each attempt would get endless immediate requests, and the list of ruled-out formats would grow without end.
- **Resolved:** at most 8 formats are ruled out for each player in a session (`UnplayableFormats.mostPerPlayer`); after that, the programme can't be played here, until its slot ends. `UnplayableTests.thereIsAMostPerPlayer`.

### P2. The privacy section said formats were read only after a failure — resolved
- **Where:** README, *Privacy*.
- **Risk:** each stream's video and sound formats are read from Jellyfin's reply for every stream (kept while it plays), not only when one fails. The docs understated what the app reads.
- **Resolved:** README says so, and gives the most formats ruled out per player.

### P3. Pull requests weren't checked by CI — resolved
- **Where:** `.github/workflows/web.yml` (only pushes to main, by design: "tested locally").
- **Risk:** a change that failed in CI was found only after it was merged, when main's build failed and the deploy was skipped (as after #58). Local runs can miss what CI's clean machine catches.
- **Resolved** (decided 2026-10-25): every pull request (into main, or into another, for a stack) runs `build` (no secrets, no environment) and `deploy-check`, which rehearses the deploy with Wrangler's dry run, also with no secrets. It's `pull_request`, not `pull_request_target`, so a pull request's run gets read access only, whoever opened it. Only `deploy`, on main, has the token.

### P4. The pinned GitHub Actions ran on Node 20 — resolved (confirmed 2026-10-26)
- **Where:** `web.yml`: checkout, upload-artifact, download-artifact and setup-node, pinned at v4.
- **Risk:** GitHub has deprecated Node 20 for actions and already ran them on Node 24 with a warning; when it's removed, the workflow fails, and with it the deploy.
- **Resolved** (decided 2026-10-25): checkout v7.0.1, upload-artifact v7.0.2, download-artifact v8.0.2, setup-node v7.1.0, each pinned by commit. Their breaking changes don't touch this workflow: download-artifact's path change is for downloads by ID (this one is by name), and v8 now fails on a checksum mismatch, which is safer. setup-node caches dependencies by itself from v5 when `package.json` names a package manager; it's turned off explicitly in the jobs that install Wrangler, since a shared cache could be poisoned. Every updated action runs in `build` or `deploy-check`, so the first pull request's run checks them all before they reach main.

### P5. A misreported decode failure rules out a format the player does play — accepted
- **Where:** `VLCItem` (VLC's error state can be the network's), hls.js's media errors after its one recovery.
- **Risk:** a transient error reported as "can't decode" rules out a format the player really plays, for the session: those files then go to another player or a conversion, more work for the server, though they still play.
- **Accepted** (the user's decision, 2026-10-25): it's bounded (P1), forgotten when the app closes, and never stops a file playing. (That last was wrong for a browser's own player, whose fetch failures look the same, and for the safest formats: see Q1, the third audit, which fixed both.) The alternative, retrying a format before ruling it out, would double the wait for a format that really can't be decoded.

### P6. More formats reach the players' own decoders — resolved, by decision
- **Where:** `PlayableFormats.vlcOnAppleTV` (TrueHD), `PlayableFormats.browser(alsoPlays:)` (HEVC, AV1, AC-3, E-AC-3, Opus, FLAC where the browser confirms them).
- **Risk:** a larger attack surface in decoders the app doesn't own (libVLC's, the browser's).
- **Resolved:** each is a format a film library really holds, confirmed by the browser itself or common enough in VLC (decided 2026-10-25, task A4); M5's rule (no rare readers) holds.

### The clean-up pass
- **Coupling:** none found; the layer check passes, and the new types sit in the layer that owns them (`MediaFormat`, `StreamContents`, `StreamRequest` in Core; `ProgrammeSettings`, `UnplayableFormats`, `ErrorKind` in Screens).
- **Duplication removed:** the "couldn't be played" error was two near-copies, one per platform: now one `UnplayableFormat` in Screens, naming the device. `PlayableFormats` spelled out its whole initializer for each changed copy: now copies change only what differs.
- **Dead code removed:** `MediaStream.Delivery.isStreamed`, used only by tests.
- **Done since** (tasks C3 to C6, 2026-10-26): timings passed in rather than set by tests (`ChannelPlayer.Timings`); the player's words in `Text/` (`PlayerText`; decks report a `DeckActivity`); the player order in one place and the fake server's options as one table; the quality map folded into PLAN §7a.

### Still open from the first audit
- **Deploys don't wait for approval:** the `gregular.tv` environment still has no required reviewer (checked 2026-10-25), so merging to main goes live at once.

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
  - Sign-in has a **Remember me on this browser** switch. Turned off, the sign-in is kept in memory for that visit only and never written to the browser (`BrowserCredentialStore.rememberNextSignIn`). It's off unless turned on, since 2026-10-26 (the user's decision: keeping a sign-in is opt-in); it was on until then.
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
  - VLC is offered only common containers (MKV, WebM, AVI, MPEG-TS, MP4/MOV, WMV/ASF, MPEG, VOB, FLV, Ogg, 3GP) and the codecs a video library really holds. The rarest readers (H.261, H.263, Dirac, FLV1, MS-MPEG4 v1/v2, Nellymoser, Speex, AMR, WavPack) are dropped, so those files are converted by the server instead. TrueHD was added on 2026-10-25: it's common in films, and without it the server had to convert their sound.
  - SwiftVLC's libVLC has no Lua, which was checked in the binary, so it runs no scripts on what it reads.
  - A test (`VLCSetupTests`) checks libVLC accepts the app's arguments (`--quiet`, and `--network-caching=3000`). Without that, it would silently start with its defaults, which log. The test caught that `--no-lua` isn't an option in this build.
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
  - `WholeFiles.checkDownload` (`OriginalFiles` until 2026-10-26) runs the same check as `JellyfinClient.download`: an allowed server, and the file on it.
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
