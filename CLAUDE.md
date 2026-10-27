# Gregular TV: start here

For a new Claude session picking this project up. It says what the project is, where everything is written down, how the owner wants work done, what has been decided, and what's open. It points to the docs rather than repeating them: when this file and a doc disagree, the doc wins, and this file should be fixed.

Last brought up to date: 2026-10-26, after PR #76 (feeds) merged.

## What it is

Gregular TV turns a Jellyfin library into always-on TV channels: a schedule worked out from a shared *schedule code*, a guide, channel surfing, commercial breaks from a `Commercials` library, your own channels and programmes at set times. It runs on **Apple TV** (tvOS 18+, SwiftUI, AVFoundation with VLC as a fallback) and in **web browsers at gregular.tv** (the same Swift compiled to WebAssembly). The repo is public; the owner works on it mostly through Claude.

**Every push to main deploys gregular.tv** (`.github/workflows/web.yml`, via Cloudflare). Treat merging as releasing.

## Read these first

| Doc | What's in it |
|---|---|
| `README.md` | What the app does for a viewer, *Run the tests*, *The web version*, *Where to edit things*, *Privacy*, *Security* |
| `PLAN.md` | The design: §2 the schedule as a pure function, §3 privacy rules, §4 architecture tree, §5 strategies, §7a stream quality (where each decision lives), §9–9c channels, rules and set times, §11 testing, **§12 every dated decision** |
| `WEB_PLAN.md` | Why and how the web version reuses the Swift code; hosting |
| `AUDIT.md` | Six security and privacy audits, newest first; every finding resolved or accepted by the owner, with dates |
| `TODO.md` | Open work, mostly checks only the owner can do on real hardware or servers |
| `FEEDS_TODO.md` | The feeds plan; its *Details I chose* still wait for the owner's confirmation (see *Open work*) |
| `COMPARISON.md` | How Gregular differs from Tunarr |

## Layers

Dependencies point one way: **GregularCore → GregularJellyfin → GregularScreens → the Apple TV app (`App/`) and the web app (`Web/`)**. `scripts/layer-check.sh` enforces it.

- **GregularCore:** schedules, strategies, rules, channels, guide maths, preferences. Foundation only.
- **GregularJellyfin:** the server connection on any platform: `HTTPTransport` and `TransportRules`, `JellyfinAPI`, `ServerAddress`, and `PublicFile` (requests that aren't to the server, such as feeds).
- **GregularScreens:** what each screen does, not how it's drawn: `AppModel`, `WatchModel`, `ChannelPlayer` (every playback decision), and every user-facing word, in `Text/`. Only four files may import GregularJellyfin: `App/AppModel.swift`, `LoginModel.swift`, `DemoCredentials.swift` and `ServerAccess.swift`.
- **The platforms only draw and play.** A decision both platforms need belongs in Screens.

The full table, with what each part may import, is in the `engineering-principles` skill's `references/gregular-tv.md` (see *Skills*).

## How the owner wants work done

These are standing instructions, repeated across many sessions. Follow them without being asked.

**Control**
- Commit, push, open PRs and merge **only when asked, each time**. One approval doesn't carry over.
- Work on a branch per task, made from main. Never force-push. Don't delete old branches; leave them.
- Ask about decisions that are the owner's (behaviour, defaults, trade-offs), with a recommendation first. When asked for a plan, give it and stop.
- Don't widen scope: do what was asked, and list anything else you noticed.
- Don't re-propose a decision already made or reversed (see *Decided*).
- Don't spawn other sessions or subagents unless asked.

**Security and privacy**
- Don't loosen security checks or the security policy (CSP) to make something work. Find another way, or ask.
- Never record the owner's server address, user ID, tokens or passwords: not in code, docs, tests, commits, PRs or memory. Use placeholders such as `nas.local` or `192.168.1.5`.
- Before anything is called ready or merged to main, the whole codebase gets the **release audit** (logged in `AUDIT.md`). Each finding is resolved, or accepted by the owner with the date.
- After a body of work, do the **clean-up pass**: no coupling across layers, no duplication, no dead code.

**Code**
- No special-case exceptions bolted onto general code. Put a decision in the layer that owns it.
- Any change to the default channels' make-up (the share of TV and films, for example) goes to the owner first.
- Match the surrounding code: its naming, its idiom, and doc comments that explain *why*. Docs refer to types and sections, never line numbers.

**Testing and reporting**
- Every behaviour change gets a test that fails without it. Run every affected suite, on every platform the change reaches.
- Every run has a hard time limit (see *Testing*). A run that hits its limit is a hang to report and fix, not a pass.
- Never disable Claude's sandbox; report the limit instead.
- Report exactly what ran, what passed, what didn't, and what's unverified, such as real hardware or a real server. Correct your own earlier mistakes as soon as you find them.

**Commits and PRs**
- Commit messages: a short imperative subject, then why. End with the attribution line the harness gives you (in 2026-10 it was `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`).
- PR descriptions follow the `pr-description` skill: **What**, **Why**, **Changes**, **Checked**. End with `🤖 Generated with [Claude Code](https://claude.com/claude-code)`.
- Merge with a merge commit, as earlier PRs were.
- After opening a PR, bind it in the app (`ccd_pr` tools) and wait for its CI event; don't poll CI.

## Skills and memory

**Skills** live outside the repo, in `~/.claude/skills/`:
- **`engineering-principles`**: the owner's principles (security, privacy, disclosure, user control, clean code, honest testing) and the two standing passes (the release audit and the clean-up pass). Load it before writing, reviewing or planning code, and before calling anything ready. Its `references/gregular-tv.md` maps it onto this repo: the layer table, the privacy allow-list, the local pages' protections, secret special modes, the test commands, and which docs to update with a change.
- **`pr-description`**: the PR format above.

**Project memory** is in `~/.claude/projects/-Users-schan141-Desktop-jellyfin-tv/memory/`. A session on the owner's Mac loads its index (`MEMORY.md`) automatically. It holds diagnoses and decisions that aren't in the repo, some because they're private. Read the relevant note before proposing a design change, or before chasing buffering or a CORS failure.

If you can't see the skills or the memory, say so, and work from this file and the docs.

## Testing

| What | Command |
|---|---|
| Package tests (Core, Jellyfin, Screens) | `scripts/bounded.sh 900 swift test` |
| Layer and privacy checks | `scripts/layer-check.sh`, `scripts/privacy-check.sh` |
| Apple TV unit tests | `scripts/test-app.sh unit [-only-testing:GregularTVTests/…]` |
| Apple TV walkthrough | `python3 scripts/demo-server.py &`, then `scripts/test-app.sh walkthrough` |
| VLC fallback walkthrough | `python3 scripts/demo-server.py --fallback &`, then `scripts/test-app.sh walkthrough -only-testing:GregularTVUITests/WalkthroughTests/test10FallbackPlayer` |
| Package tests in WebAssembly | `scripts/test-web.sh unit`, about 17 minutes, mostly the core tests |
| Browser-layer tests | `scripts/test-web.sh browser` |
| Web build | `scripts/build-web.sh debug\|release` |
| Web walkthrough (Chromium, WebKit, Firefox) | `scripts/test-web.sh walkthrough [release]` |

CI on a PR runs only the layer and privacy checks, the browser-layer tests and the release walkthrough. The package, WebAssembly and Apple TV suites run only locally, so run them before asking to merge.

**Traps, each of which has cost hours:**
- **Time limits.** `scripts/bounded.sh SECONDS cmd` kills a run that overruns (the test scripts already use it). macOS doesn't count time asleep, so if the Mac sleeps, a run can go well past its limit. Long runs go under `caffeinate -i`, which keeps the Mac awake for that command only.
- **No `.timeLimit` in Core, Jellyfin or Screens tests.** In WasmKit, every test under one runs to the full limit and fails.
- **A long `Task.sleep` hangs WasmKit.** Its run can't end while any sleep is queued, even a cancelled one. Anything that repeats needs a way for tests to turn it off: `AppModel(checksFeedsEvery: nil)` does this for the feed check. A WebAssembly suite that prints only "started" lines at 0% CPU is this.
- **Stale WebAssembly objects.** After deleting or renaming a Swift file, or switching branches, run `rm -rf .build/wasm/out` before `scripts/test-web.sh unit`.
- **The simulator.** Apple TV tests run on the **"GregularTV Tests"** simulator. Never use the one the owner watches on (`C9B62EDD-C286-4444-9FB6-7AAF9F3C5D1E`): a test run reboots its simulator.
- **DNS back-off.** AVFoundation waits longer each time it retries a host it couldn't resolve. App tests give each client its own `.invalid` host.
- **Ports.** The walkthroughs use 8765 (the demo server) and 8090 (the web build). Playwright reuses whatever is already listening there, so check nothing stale is running first.
- **Flaky Apple TV unit tests.** `AppleTVSoundTests.applesPlayerPlaysIt`, `StreamStabilityTests.aStreamThatFailsIsRetriedNotTreatedAsFinished`, and two `ProgrammeFixTests` sometimes fail in full runs, with the simulator's audio timing out. They fail the same way on main and pass when run alone. All 49 passed in the last full run (2026-10-26).
- **The demo server** (`scripts/demo-server.py`) signs anyone in and serves made-up public-domain content. It also serves feeds for the walkthroughs: `/feeds/silent-comedy.json`, and `/feeds/changing/<name>.json`, which serves an update from its second request.

## Decided

Don't re-propose these. Dated details are in PLAN §12 and AUDIT.

- **Playback:** AVFoundation first, VLC only for files it can't play, plus the viewer's *Play in VLC* switch. VLC-first was tried in PR #59 and scrapped.
- **Invisible to the Jellyfin dashboard:** no playback reporting, no "played" marks, no toggle for it.
- **Nothing kept that isn't needed to play video:** no analytics, no logging, no disk cache. The web's *Remember me* is opt-in, encrypted and off by default.
- **Stream quality:** *Auto* plays the original until there's trouble on the connection (PLAN §7a).
- **Default channels:** remade as eras, laid out like cable before streaming (PRs #72–#74).
- **Channels whose content changes by time of day (dayparting):** a future idea only. Don't build it unasked.
- **Feeds** (2026-10-26, PR #76):
  - Our own JSON at an https link, not RSS. A feed brings only its own channels, and set times on them, in a block of ten numbers the follower picks.
  - The first version is taken when you follow; later updates wait for one tap (*Get Update*), shown by a dot on Settings.
  - Feeds are checked at launch, then every 6 hours. No proxy for the web, so a feed's host must allow web apps to read it.
  - Feed channels can't be edited, only copied (*Make a Copy*). Unfollowing removes everything the feed brought.
  - An optional picture: a small PNG, checked before it's decoded.
  - AUDIT T1 (what a feed's host learns) and T2 (decoding a stranger's picture) were accepted by the owner. TODO item 8 is to think later about telling a host less.
- **Secret special modes:** their keywords are stored only as hashes. Never write a keyword anywhere, and keep the modes out of README and other user docs (`references/gregular-tv.md`, *Secret special modes*).
- **CORS failures seen from the owner's work network** come from its proxy, not the app. Don't change the app for them.
- **The leg between the owner's server and their relay** is handled elsewhere. Don't raise its security again.

## Open work (as of 2026-10-26)

- **Feeds**, merged, needing the owner:
  - confirm or change *Details I chose* in `FEEDS_TODO.md`, then fold what lasts into README and PLAN and delete that file;
  - a real host: done on 2026-10-26 with a secret gist, and the owner confirmed that following and Get Update work. The gist is kept as the test case for feeds. Its link is in project memory (`test-feed-gist`), not here, because this repo is public. Ask the owner before editing it. GitHub Pages hasn't been tried;
  - check how the Feeds section looks on a real TV;
  - save a feed file from the Apple TV's editing page on a real phone.
- **`TODO.md`:**
  - checks on real hardware and the real server: buffering, the editing page, gregular.tv against a real server;
  - backlog item 7 (feeds setting times on your own channels) and item 8 (what a feed's host learns).
  - **Item 4's "signing in all the way" is stale:** the demo server now signs anyone in, and the walkthroughs sign in. Fix it in its own change.
- **Quality work** (PLAN §7a, *Still open*):
  - FLAC and 7.1 on Apple's player on a real Apple TV;
  - whether Jellyfin starts ffmpeg twice when joining part-way (needs the owner's server log);
  - a commercial stutter on the web, reported but unconfirmed;
  - the special mode's walkthroughs, which need its keyword from the owner.
- **Flaky tests:** the Apple TV unit tests above, and the Apple TV sign-out walkthrough now and then.
