# Gregular TV

*We now return to your Gregular programming.*

A Jellyfin client for Apple TV, and for web browsers at [gregular.tv](https://gregular.tv), that plays your library as always-on TV channels. See [PLAN.md](PLAN.md) for the design, and [WEB_PLAN.md](WEB_PLAN.md) for the web version's.

## IMPORTANT NOTE: 
This is mostly AI coded. Why does this exist? I wanted a better shuffle algorithm than what I found in existing applications and I didn't want to make the rest of the bones just to watch videos from a Jellyfin server. I wrote the shuffle algorithm myself in python and had it translated to Swift by the LLM. It's mostly for personal use, but it's open source regardless. Have fun!

## Status

Version 1.2. All seven milestones in [PLAN.md](PLAN.md) are done. The core package handles scheduling, the Jellyfin client and privacy, and the tvOS app has a main page of your servers (several at once), sign-in, live channels, surfing, a six-hour guide, quality settings, commercial breaks (including mid-roll breaks in films) from a Jellyfin library named `Commercials` (see PLAN.md §9a), your own channels, and programmes at set times, made on the editing page.

Open `App/GregularTV.xcodeproj` in Xcode and run the **GregularTV** scheme on an Apple TV simulator or device. Requires tvOS 18 or later and Jellyfin 10.9 or later.

The web version (`Web/`) runs the same schedule, sign-in and screen logic, compiled to WebAssembly, in Chrome, Edge, Safari and Firefox, on phones first and up to TVs: see *The web version*, below.

## Install on an Apple TV

1. In Xcode, select the **GregularTV** target › *Signing & Capabilities*, and choose your **Team**. If Xcode says the bundle identifier is taken, change `dev.gregulartv.GregularTV` to one of your own (for example `com.yourname.gregulartv`).
2. Pair the Apple TV: on the Apple TV, *Settings › Remotes and Devices › Remote App and Devices*; in Xcode, *Window › Devices and Simulators*.
3. Choose the Apple TV as the run destination, set the scheme's *Run* build configuration to **Release** (*Product › Scheme › Edit Scheme*), and press Run. Release builds leave out every debug option.

With a free Apple ID the app has to be reinstalled every 7 days; a paid developer membership makes that a year, and TestFlight works for sharing it.

The project is ready for TestFlight and App Store uploads: it includes Apple's privacy manifest (`App/GregularTV/PrivacyInfo.xcprivacy`: no tracking, no data collected, `UserDefaults` for the app's own settings only, reason CA92.1) and declares that it uses only exempt encryption (`ITSAppUsesNonExemptEncryption = NO`), so App Store Connect doesn't ask about export compliance for each build. In App Store Connect's privacy questions, the matching answer is **Data Not Collected**.

**Signing for upload.** Debug builds sign automatically (Apple Development). Release builds for a real Apple TV sign manually with **Apple Distribution** and the App Store profile named **Gregular TV App Store**, so archiving doesn't need a registered device. To upload: choose **Any tvOS Device (arm64)**, then *Product › Archive*, then *Distribute App › App Store Connect*. Raise the build number for every upload. The profile expires after a year: renew it on developer.apple.com (*Profiles*), download it and double-click it. If you use a different team or profile name, change `PROVISIONING_PROFILE_SPECIFIER` in the target's Release build settings.

## Run the tests

The logic, the Jellyfin connection and the screens (on fake video decks), on the Mac. This also runs the privacy and layer checks:

```bash
swift test
```

App-hosted tests (Keychain), on the tvOS simulator:

```bash
xcodebuild test -project App/GregularTV.xcodeproj -scheme GregularTV -destination 'platform=tvOS Simulator,name=GregularTV Tests'
```

Run app tests on a dedicated simulator ("GregularTV Tests"), not the one you're watching. A test run reboots its simulator, which freezes any live view attached to it.

## The web version

The same app in a web browser: the shared Swift code (`Sources/`) compiled to WebAssembly, with web pages for its screens, `<video>` for playback and the browser's network and storage (`Web/`, its own package). Everything happens in the browser: the site only serves the app's files, and the browser talks to your Jellyfin server directly. Phones come first (the picture at the top, what's on and the controls under it, every channel's now and next below), then landscape, tablets, desktops and TVs.

**Which servers it can reach.** A web page on https can't talk to a plain http server, so:

| Your server | Chrome, Edge | Safari, Firefox |
|---|---|---|
| `https://…` | ✅ | ✅ |
| `http://` on your home network (`192.168.x.x`, `name.local`, `nas:8096`) | ✅ after allowing "local network" access | ❌ |

From an http server the browser asks for every programme as HLS (usually just a change of container, which is cheap for the server), since it can't play a file over http.

**Controls.** Touch: tap the picture for the controls, swipe across it to change channel. Keyboard (the same tables as the Siri Remote, `KeyboardControls`): ← → channels, I info, L channel list, S Settings, Space pause or jump to live, Esc steps back (banner, guide, servers), digits type a channel number. Everything works with a screen reader, at any text size, and with reduced motion.

**Build and run it locally.** Needs the swift.org toolchain 6.4.0 and its WebAssembly SDK (Xcode's Swift can't build for the browser), and `wasm-opt` (`brew install binaryen`) to shrink release builds:

```bash
swiftly install 6.4.0
```

```bash
~/Library/Developer/Toolchains/swift-6.4.0-RELEASE.xctoolchain/usr/bin/swift sdk install https://download.swift.org/swift-6.4.0-release/wasm-sdk/swift-6.4.0-RELEASE/swift-6.4.0-RELEASE_wasm.artifactbundle.tar.gz --checksum f07b7be3c586d92d7a07051fc6d303b87ebea67eadc40640ba59d5a8b79aa86d
```

```bash
scripts/build-web.sh debug
```

```bash
python3 scripts/serve-web.py
```

Then open http://localhost:8080. With `python3 scripts/demo-server.py` running too, sign in to `127.0.0.1:8765` with any name, or (Debug builds) open http://localhost:8080/?demoServer=http://127.0.0.1:8765. `scripts/serve-web.py` sends the same security headers as gregular.tv (`Web/public/_headers`).

**Test it.** The walkthrough drives the app in Chromium, WebKit and Firefox with Playwright, against the demo server; the unit run builds the package's own tests for WebAssembly (a 32-bit platform, unlike the Mac) and runs them in WasmKit, which takes about 20 minutes:

```bash
cd Web && npm install && npx playwright install chromium webkit firefox
```

```bash
scripts/test-web.sh walkthrough
```

```bash
scripts/test-web.sh unit
```

The browser layer's own tests (`Web/Tests`) run in Node:

```bash
scripts/test-web.sh browser
```

**Deploying** is automatic: `.github/workflows/web.yml` builds, checks and tests every push, deploys main to gregular.tv on Cloudflare, and gives each pull request a preview address. Setting up the domain and Cloudflare is in [WEB_PLAN.md](WEB_PLAN.md), *Hosting at gregular.tv*.

## Schedule code

Every channel's running order comes from one 10-character **schedule code** (like `7KQM2-X9PDA`), shown and editable in Settings (click and hold while watching). The first launch picks a random one. Two Apple TVs with the same code, the same Jellyfin library and the same `channels.json` show the same programmes at the same time on every channel. Changing the code reshuffles everything. See PLAN.md §9b for how the code becomes each channel's shuffle.

## The channels

Sixteen channels ship in `channels.json`. Channels 1–9 are themes that mix TV and films: Gregular (everything), Comedy, Drama, Animation, Sci-Fi & Fantasy, Kids & Family, Real Life (documentaries, reality, cooking, travel and the like), Crime & Mystery, and Action & Adventure. Channels 10–16 are films only: Movies, Action, Comedy, Horror & Thriller, Classics (before 1980), Sci-Fi & Fantasy, and Drama & Romance.

The line-up adapts to the library you connect to, with nothing to set:
- **A themed channel only appears if it has variety:** enough different programmes to fill a day with no series coming round more than about once a day, and no film more than about once every three days. A small library shows fewer channels; Gregular and Movies are always on.
- **Each mixed channel asks for a share of airtime for films** (`"films": 0.35` is 35%), and the library can move it: a channel with few series fills the rest with films, and one with few films fills it with TV. The series and the films each keep their own shuffle. See PLAN.md §9.

Each channel's day starts at midnight Pacific (3 AM Eastern), daylight saving and all: that's where one day's shuffle meets the next, so the odd programme from the evening can come round again soon after. Programmes play right up to the end of the day; whatever time a day can't fill is a break just after it starts, before its first programme, which on a film channel can run long. The day boundary is one setting, `DayBoundary.standard` (in GregularCore).

## Your own channels and set times

Your own channels and set times are made on the **editing page**, in a web browser on a phone or computer on your home network, where there's a keyboard and search. Settings on the Apple TV lists them, but doesn't change them. The page is **off by default**, so out of the box there are only the bundled channels.

**To edit:** turn on **Settings › Edit from a phone or computer › Editing page**, then choose **Open the Editing Page**. The TV shows an address (like `http://192.168.1.20:8080`) and a six-digit code. Open the address, type the code, make your changes, and choose **Save to Apple TV**: the channels are rebuilt straight away.

**A channel** has a name, a number from 20 to 99, episodes or movies or both, and a rule of up to 20 conditions on genres, series, tags and years (your library's names are suggested as you type). Each condition joins the rest one of three ways:
- **Any of:** a programme needs to match at least one of these (none of them means everything).
- **All of:** it must match every one.
- **None of:** it's left out.

So "any of Comedy and Taskmaster, none of Christmas" is comedy or Taskmaster, but nothing tagged Christmas. Half-hour slots and commercials are on by default. **Preview** shows how many programmes match and the next few hours as they'd air. Your channels join the guide like any other, and are hidden while nothing matches. Changing a channel's number takes its set times with it; deleting it deletes them.

**Sharing:** the page's **JSON** tab shows all your channels and set times as one document. Copy it, and paste it into another Apple TV's page (then **Use This JSON** and save) to have the same there: with the same schedule code, both show the same programmes.

**The page only exists while its screen is open on the TV**, and closing the screen stops it. It answers only devices on your home network, at the address shown, with the code. Five wrong codes from one device shut that device out, and 20 in all lock the page, until you close and reopen the screen. The page isn't encrypted, so use it on a network you trust. It loads nothing from the internet, and it never sees your Jellyfin address, password or token: only your genre, series, tag and film names. Everything it saves is checked before it's used.

## Programmes at set times

A channel can air certain programmes at set local times, such as a series at 6:00 and 6:30 PM on weekdays, or a film every 2 February. Set times are laid **over** the channel's shared schedule: while one is on, its programme is; the rest of the time the channel is exactly what everyone with the same schedule code sees, joined partway through a programme if one was already on. So a household can add set times without drifting out of step with the people it shares a code with.

Set times are made on the editing page (above), on any channel, bundled or custom, in a time zone you choose (the Apple TV's, to start with). A channel can also ship with set times in `channels.json`:

```json
"timeZone": "America/New_York",
"fixed": [
  { "series": "The Simpsons", "at": ["18:00", "18:30"], "days": ["Mon", "Tue", "Wed", "Thu", "Fri"] },
  { "item": "Groundhog Day", "at": ["20:00"], "days": ["Feb 2"], "exclusive": true }
]
```

A series plays its next episode at each airing. `exclusive` (*Only at these times* on the editing page) means it only airs then: wherever the shared schedule would air it otherwise, another programme stands in for that slot, and nothing else moves. See PLAN.md §9c.

## Special rules

A few things hold whatever a channel's strategy, and they're all in one registry, `ScheduleRules` (`Sources/GregularCore/Rules/`):
- **The same movie (or the same episode) never airs twice in a row.** A show may follow itself with its next episode.
- **The same commercial never plays twice in a row.**
- **Programmes at set times air at exactly those times**, over the shared schedule, a series advancing one episode per airing.
- **An exclusive set programme only airs at its set times**: its other airings get a stand-in.
- **Set times are checked** when the line-up loads: a time zone, and no two programmes at the same time on the same day.
- **Custom channels use 20 to 99**, and no two channels share a number.
- **Set times belong to a channel in the line-up**, one set per channel.

See PLAN.md §9c for how the engine keeps them.

## Commercials

Every programme starts on the half hour. The time from its end to the next half hour is commercials, from a Jellyfin library named `Commercials` (the name is set in `channels.json`):
- **After a TV episode:** all of it, after the episode. An episode an hour or longer is treated like a film, below.
- **In a film:** a film's leftover can be up to half an hour. Up to 10 minutes goes after the film. More is shared out evenly between the break after it and one or two **mid-roll** breaks inside it (halfway, or at a third and two thirds), each 10 minutes at most: one mid-roll for up to 20 minutes, two beyond that. At least 15 minutes of film plays between breaks, so a short film gets fewer mid-rolls (none under 30 minutes) and the rest goes after it. The film stops at the break and carries on from the same point after it.
- Each pass through the commercials plays every clip once, in a new shuffle (independent of the show order), carrying on from break to break. The same clip never plays twice in a row.
- **At most 20 minutes of commercials in one break.** A longer break (after an episode that ends well before the half hour, a short film, or at the end of a day) is blank after that, with the "Up next" card, and the programme still starts on time.
- A gap of a minute or less gets no commercials. When a clip ends, the next only starts if at least half of it will play before the last 15 seconds; otherwise the rest of the break is blank. A clip still playing then is cut off.
- The last 15 seconds of every break with commercials are the **station card**, like a TV station's ident: "You're watching" the channel, the Gregular wordmark with its colour bars hopping to a short marimba tune, and what's up next. The last commercial fades out quickly into it, then the card fades to black and the programme fades in. With commercials off (or none in the library), breaks keep the plain "Up next" card, with no music.
- Every clip plays: one the device can't play as it is (for example, a video codec the Apple TV can't play) is converted by Jellyfin, as a programme would be. There's no bitrate cap for commercials, so the quality setting never makes one re-encode. **MP4, 8-bit H.264/AAC** plays as it is everywhere, costing the server nothing; keep the bitrate modest if you watch over a slow remote connection.
- The screen is blank during any unfilled time, with an "Up next" card showing when the next programme starts, or during a film's mid-roll, a "Now playing" card saying when it's back.
- It's always clear when the programme is over: while commercials play, a small **Commercial break · Back at 9:30 PM** badge sits in the top corner (the banner comes and goes as usual). The channel list shows **Up next: …** with **Commercial break · starts 9:30 PM**, and the guide draws each programme's break as a darker tail on its block.
- **Settings › Commercials › Play commercials** turns them off: every break, mid-rolls included, is blank. Programme times don't change, so you stay in step with everyone on the same schedule code.

## The main page and your servers

The app opens on its **main page**: the Jellyfin servers you're signed in to, the one you watched last first and highlighted, and **Add a Server**. A click on a server (or Play/Pause, for the one watched last) starts its live TV, on the channel you watched last. Hold a click on a server to sign out of it. Menu on the main page goes to the Apple TV Home screen.

Each server is a sign-in kept in the Keychain. The page shows a server's address, and its name once the server answers (asked each time the page shows, never stored). Your schedule code, channels and set times are the same on every server: a name a library doesn't have just doesn't match there.

**Menu, one step at a time:** live TV → guide → **Resume Live TV** → main page → Home screen. While watching, Menu opens the guide (after hiding the banner, if it's up). In the guide, Menu moves up to the top row, onto **Resume Live TV**, next to Settings; a click there goes back to the channel. Menu again goes up to the main page, and the channel carries on playing, dimmed, behind it. Your server is marked **Now playing**, so a click (or Play/Pause) goes straight back to the channel, without loading or re-tuning. Settings also has **All Servers**.

## Remote controls

**To change what a button does,** edit the tables at the top of `Sources/GregularScreens/Remote/RemoteControls.swift`: one per screen (the main page, watching, channel list, guide, Settings), each a list of `button: action`. The hints on screen are written from the same tables. As shipped, while watching:

The app starts on the main page (above). "Click" means pressing the pad down; "slide" means moving a finger across it; a "light touch" is touching it without clicking. In the Simulator, the arrow keys are clicks on the edge of the pad, Return is a click, the space bar is Play/Pause and Escape is Menu; the Simulator can't slide or touch.

A light tap anywhere on the pad, edges included, only brings up the banner; only a real click on the left or right edge changes channel. (Most Siri Remotes report every click on the pad as a centre click, so the app reads where your finger is when it clicks: past halfway to an edge is that edge's click. With the remote's "Click and Touch" setting, tvOS also turns a light tap on the edge into an arrow press just after the finger lifts; the app ignores those. If an edge tap ever changes the channel, set the Apple TV's **Settings › Remotes and Devices › Clickpad** to **Click Only**.)

| Input | Action |
|---|---|
| Click left / right (edge of the pad) | Channel down / up (the banner previews each channel, and tunes when you stop; the picture fades out while you surf and back in once the new channel plays) |
| Slide left | Channel list; Select tunes. Slide right, Menu, or 15 s idle closes it and stays on the current channel. Play/Pause opens Settings |
| Light touch (a click touches the pad too) | Show the info banner (clock, progress, time in). Again while showing: switch between end time and time left |
| Menu (or Back ‹) | If the banner is up, hide it. Otherwise the programme guide, six hours ahead, scrolling sideways; Select on a programme tunes to its channel, **Resume Live TV** (top row) goes back to the channel, and 60 s idle closes it. In the guide, Menu first moves up to Resume Live TV (highlighted, not pressed); Menu again goes up to the main page, with the channel playing on behind it (a click goes straight back). On the main page, Menu goes to the Home screen |
| Click and hold | Settings: streaming quality, trouble with this programme (step down quality, 720p, standard), schedule code, your channels and set times, the editing page, commercials, match frame rate, diagnostics, and the server (All Servers, Sign Out). In the guide, it's the button next to Resume Live TV. Close with Menu, Play/Pause or Done |
| Play/Pause | Pause; press again to jump back to live |
| Digits (keyboard only) | Type a channel number |

## Debug options

Debug builds accept launch arguments. Release builds leave them out entirely.

| Argument | Effect |
|---|---|
| `-handoffTest` | Shifts every channel so the current programme ends about 50 s after launch, to test the hand-off to the next programme quickly. |
| `-breakEndTest` | Shifts every channel so launch lands 8 s before the end of the last commercial in a break between two programmes, to watch the fade into the Up next card and the programme without waiting. Add `late` (`-breakEndTest late`) to start that commercial from its beginning, so it runs late, as after a slow load. |
| `-openChannelList` | Opens the channel list on launch, to check its focus handling without arrow keys. |
| `-openGuide` | Opens the guide on launch, to check it without a remote. |
| `-pretendCommercials` | Uses a dozen library videos, cut to 30–120 s, as commercials, to test breaks without a `Commercials` library. |
| `-openSettings editingPage` | Opens Settings, then the editing page's screen (whether or not its switch is on). |

```bash
xcrun simctl launch booted dev.gregulartv.GregularTV -handoffTest
```

**Remote keys in a Release build, for the simulator.** Debug builds let letter keys stand in for remote buttons the keyboard lacks (`m` Menu, `p` Play/Pause, `h` click and hold, `t` touch, `w`/`a`/`s`/`d` slides; see `RemoteControls.debugKeys`). To test the production build the same way, build it for the simulator with the `REMOTE_KEYS` flag. The keys only exist in a simulator build, so the flag can't reach an Apple TV or the App Store:

```bash
xcodebuild build -project App/GregularTV.xcodeproj -scheme GregularTV -configuration Release -destination 'platform=tvOS Simulator,name=GregularTV Screenshots' 'SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) REMOTE_KEYS'
```

**A walk through every screen with the remote.** The `GregularTVWalkthrough` scheme runs UI tests (`App/GregularTVUITests`) that drive a simulated Siri Remote through watching, the guide, Settings, both editors, the confirmations, codes and signing out, against the demo server, never a real one. They save a screenshot at each step to `TEST_RUNNER_SHOTS_DIR` for a person to look over. They take a few minutes, so they're kept out of the `GregularTV` scheme's tests:

```bash
python3 scripts/demo-server.py
```

```bash
TEST_RUNNER_SHOTS_DIR=/path/to/shots scripts/test-app.sh walkthrough
```

`scripts/test-app.sh unit` runs the app's own tests the same way. The script stops a run that goes over its time limit, and turns off xcodebuild's diagnostics collection: after any failing test, xcodebuild otherwise waits up to 10 minutes on a `simctl diagnose` of the simulator once the tests are done. Extra options go to xcodebuild, such as `-only-testing:GregularTVUITests/WalkthroughTests/test7MainPage`; `DESTINATION=…` picks another simulator.

**Playback diagnostics** are a setting, not a build type: turn on **Show playback diagnostics** in Settings (click and hold while watching) to add a technical line to the banner. It shows quality, whether the server is transcoding and why, buffering, and how far behind live playback is. It's off by default. It never shows the server address, token, user or stream URLs.

**Auto quality** plays the original file, with no bitrate cap, until playback has trouble on the connection (a failure, a stall, or falling a minute behind live). Only then does it measure the connection and cap the bitrate, because a cap below a file's own bitrate makes Jellyfin re-encode it, which a small server such as a Raspberry Pi can't do in real time. **Subtitles are off**: the app asks Jellyfin for none, so it never burns them into the video (another full re-encode). A subtitle track inside a file that plays as-is follows the Apple TV's own Subtitles setting.

**When Jellyfin can't re-encode fast enough** (a slow server converting a file the Apple TV can't play as-is), a programme that fails, stalls or falls a minute behind live is retried with less work: 720p, then a step lower on each further failure, for that programme only (Settings shows it as the programme's fix). A programme Jellyfin would re-encode isn't started with under 3 minutes left; the screen shows "Up next" instead, so the server isn't asked for an expensive transcode for a minute of video.

## Where to edit things

| I want to… | Edit |
|---|---|
| Understand how the code is split | Four parts: the logic (`Sources/GregularCore`), the Jellyfin connection (`Sources/GregularJellyfin`), what the screens do (`Sources/GregularScreens`) and Apple TV itself (`App/`); see `Package.swift` and PLAN.md §4 |
| Change what the screens do or say (banner, cards, overlays, fades) | `WatchModel` in `Sources/GregularScreens/Watch/WatchModel.swift`; the Apple TV views in `App/GregularTV` only draw it |
| Play video some other way | Implement `PlayerDeck` (`Sources/GregularScreens/Player/PlayerDeck.swift`), as `TVDeck` does for Apple TV and `VideoDeck` (`Web/Sources/GregularWeb/Player`) for the web |
| Change the web version's look | `Web/public/app.css` (its design tokens are at the top; phones first, larger screens in the media queries at the end) |
| Change what the web version's screens show | `Web/Sources/GregularWeb` (pages in `Pages/`, live TV in `Watch/`); the words come from GregularScreens, as on Apple TV |
| Change the keys on the web | `KeyboardControls` in `Sources/GregularScreens/Remote/KeyboardControls.swift` (which remote button each key presses) |
| Connect a different media server | Implement `MediaLibrary` and `StreamSource` (`Sources/GregularCore/Services/MediaServices.swift`), and use it in `AppModel` |
| Change the channel line-up | `Sources/GregularCore/Resources/channels.json`, then run `swift test` to validate it |
| Change how much variety a themed channel needs, or how a mix gives way | `ChannelVariety.seriesDays` and `filmDays` in `Sources/GregularCore/Scheduling/ChannelVariety.swift`; a mixed channel's `"films"` share in `channels.json` |
| Check the line-up's variety and the shuffle's evenness | `SCHEDULE_AUDIT=1 swift test --filter ScheduleAudit` (about 25 seconds; prints `AUDIT` lines) |
| Add a shuffle/scheduling algorithm | New file in `Sources/GregularCore/Scheduling/Strategies/`, then add it to `StrategyRegistry.all` |
| Add a special rule (something that must hold on every channel) | A type in `Sources/GregularCore/Rules/` conforming to one of the rule kinds in `ScheduleRule.swift`, then add it to `ScheduleRules.all` |
| Add a way to choose channel content | New type in `Sources/GregularCore/Channels/Sources/`, then add it to `ChannelSourceRegistry.all` |
| Change the order commercials play in | New `GapFiller` in `Sources/GregularCore/Scheduling/GapFiller.swift`, then add it to `GapFillerRegistry.all` and set `"filler"` in `channels.json` (see PLAN.md §9a) |
| Change what the remote's buttons do | The tables at the top of `Sources/GregularScreens/Remote/RemoteControls.swift` (one per screen) |
| Change how long a mid-roll may be, how many a film gets, how long an episode must be to get them, or the Up next lead | `ChannelSchedule.longestMidRoll`, `maxMidRolls`, `longEpisode` and `upNextLead` in `Sources/GregularCore/Scheduling/ScheduleEngine.swift` |
| Restyle the icon or Top Shelf image | `scripts/make-artwork.swift`, then run `swift scripts/make-artwork.swift` |
| Take App Store screenshots | Demo mode (Debug builds only): run `swift scripts/make-demo-video.swift` once, then `python3 scripts/demo-server.py`, and launch the app in a simulator with `-demoServer http://localhost:8765`. It plays public-domain films and made-up shows, with nothing saved to the Keychain. See `App/GregularTV/DemoMode.swift`. |

### Adding a strategy

A strategy is an endless stream of programmes, like a Python generator. The engine pulls them one at a time through a day-long run, and never asks for a channel's whole schedule.

```swift
/// Any programme at random, each time; repeats allowed. Example only.
struct PureRandom: ScheduleStrategy {
    static let id = "pure-random"            // used in channels.json
    static let displayName = "Pure Random"

    func programmes(from content: ChannelContent, startingAt position: Int, rng: SeededRandom) -> AnyIterator<MediaItem> {
        var rng = rng
        return AnyIterator { content.items[rng.int(below: content.items.count)] }
    }
}
```

The rules are documented on `ScheduleStrategy`:
- **Never end:** wrap around or reshuffle.
- **Be deterministic.**
- **Continue from `position`** if your order is a sequence.
- **Randomness:** use only the `rng` you're given, or `ShuffledOrder` with `content.seed`. `SeededRandom` is deliberately *not* a `RandomNumberGenerator`, because the standard library's shuffle can change between Swift releases.

`StrategyConformanceTests` checks all of this for every registered strategy automatically.

## Privacy

Gregular TV is built to know as little as possible about your Jellyfin server, and to keep even less.

**Stored on the Apple TV (and nothing else):**

| What | Where | Why |
|---|---|---|
| For each server you're signed in to: its address, access token and user ID, the one watched last first | Keychain, this device only (excluded from backups and iCloud) | To reconnect without signing in again, and to list your servers on the main page |
| A random device ID for each sign-in | Keychain, with the sign-in | Jellyfin requires one. Each sign-in has its own, so two servers can't tell they're talking to the same Apple TV |
| Last channel number, streaming quality, schedule code, the diagnostics, commercials, editing-page and frame-rate switches | App preferences | Client settings; no server data |
| Your custom channels, packed as short codes | App preferences | What you typed or picked: a name, a number, and the genres, series, tags and years in its rule |
| Your set times, packed as short codes | App preferences | What you typed or picked: a channel number, the series or film names, the times and days, and your time zone |

**Never stored:** your password (it's used for one sign-in request only), your library (titles, episodes, artwork; a custom channel or set time keeps only the names you picked for it), schedules, watch history, or logs. The library is fetched into memory at launch and is gone when the app quits. Schedules are recomputed from each channel's seed and the clock, so there's nothing to save.

**Deleting the app** leaves nothing that comes back: the Keychain can keep an app's items after it's deleted, so on its first launch after installing, the app forgets every sign-in it finds.

**Never reported to Jellyfin:** your watch history. The app makes no playback-reporting calls, so nothing appears under "Now Playing" and your watched status and resume points are untouched. It never opens the live connection Jellyfin sends remote control over, so other Jellyfin apps can't control it.

**The editing page** (off unless you turn it on): while its screen is open, a browser on your home network can see your channels and set times and the genre, series, tag and film names the editors offer, as the Apple TV's own Settings shows them. Nothing about the server itself, and nothing is kept or sent anywhere else.

**What Jellyfin can still see:** a sign-in in its activity log, this Apple TV (named just "Apple TV") in its device list, and the stream requests themselves, as for any client. Those say which programme each stream is, since the server has to know what to send, and its logs may keep them. Stream addresses carry the sign-in as `ApiKey`, as with every Jellyfin client, so they can also appear in a reverse proxy's logs. Before signing in (checking an address), and when the main page asks a server its name, the app sends nothing about this device.

**Enforced, not just promised:**
- **Network:** all the app's own requests go through one ephemeral `URLSession`, with no disk cache and no cookies. Video itself is fetched by Apple's player (AVFoundation), or VLC for a file Apple's can't play as it is, from the stream addresses your server gives, which always point back at your server.
- **Privacy check:** [`scripts/privacy-check.sh`](scripts/privacy-check.sh) fails the app build, and `swift test`, if code outside the three allowed files uses anything that persists or leaks data. That covers `UserDefaults`, files, Core Data and SwiftData, caches, cookies, the Keychain, iCloud storage, and system logging (`Logger`, `os_log`, `NSLog`, `print`).
- **Tests:** they check that no playback-reporting endpoint is ever called (the one call near them is the transcode keep-alive, which names only the play session the server made for a stream), that sign-out clears credentials even when the server is unreachable, and that preferences hold only the client settings and the custom channel and set-times codes.
- **No third-party analytics or crash reporting.** The one library that isn't Apple's is VLC ([libVLC](https://www.videolan.org/vlc/libvlc.html), through [SwiftVLC](https://github.com/harflabs/SwiftVLC)), which plays files Apple's player can't play as they are; it fetches only the stream it's given, and keeps nothing. The app sends Apple nothing itself; only tvOS's own *Share Analytics* setting (the device owner's choice) sends crash reports.
- **Privacy manifest:** `PrivacyInfo.xcprivacy` declares the same to Apple: no tracking, no data collected.
- **Artwork:** the app icon and Top Shelf image are drawn by [`scripts/make-artwork.swift`](scripts/make-artwork.swift), never taken from your server.

**In the web version,** the same holds, in the browser's terms:
- **Nothing goes to gregular.tv** but requests for the app's own files: no analytics, no logs of yours, nothing from your server. The browser talks to your server directly, and video comes straight from it.
- **Your sign-ins** are kept in the browser's IndexedDB, encrypted with a key the browser makes for this site and won't let even the page read out. Your preferences, channels and set times are in its local storage, as on Apple TV. Settings › *Forget Everything* signs out of every server and deletes both.
- **Enforced:** every request goes through `fetch()` with no cookies, no cache and no referrer, and no redirect is followed at all. The privacy check covers the web code too (local storage only in `BrowserPreferences.swift`, IndexedDB only in `vault.js`, no console logging), and the Playwright walkthrough checks that local storage holds no sign-in and the vault holds nothing readable.
- **What your server sees** is as for the Apple TV app, with the device named "Web Browser", plus what every browser sends (its user agent, and that the request came from gregular.tv).

## Security

The app treats what reaches it as untrusted: the server's replies, codes typed in from anywhere, and whatever the editing page is sent.
- **Your sign-in stays with your server.** A redirect is followed only on the same server (or from `http` up to `https` on the same host), so a password or token is never passed on elsewhere. Plain `http` is refused beyond your home network (local names like `nas` or `tv.local`, and private addresses like `192.168.1.5`), so a password never crosses the internet unencrypted. For anything else, including Tailscale, use `https`. Signing in over plain `http` says so on screen, and suggests Quick Connect, which keeps your password off the network. These rules are in the shared code, so any future version of the app keeps them.
- **An administrator's sign-in is your choice.** Signing in as an account that can change the whole server asks first, since the TV keeps the sign-in and sends it with every video; an account without admin rights is safer. Choosing another account cancels that sign-in on the server.
- **Only an expired sign-in signs you out.** The server saying no to one request (HTTP 403, for a programme the account may not watch, say) is an error, not a sign-out. Signing out tells the server to cancel the sign-in; if it can't be reached, the app says how to cancel it from the server's dashboard. A Quick Connect code left on screen stops working when you leave sign-in, and a password typed for one server is never sent to another.
- **A misbehaving server can't take the app down.** The item count a server claims is capped, paging stops at the first empty page, each page counts for at most one page of items, the whole library listing holds at most 64 MB of names, and any reply over 16 MB is stopped as it arrives. Stream URLs from the server keep only their path and query, so they always point back at your server. Item names are shown as plain text, never as formatting or links.
- **What the editing page saves can't do more than change your own schedule.** It carries only names, numbers and times, and it's checked like the app's own settings before it's used: numbers from 20 to 99 and not taken, at most 20 conditions on a channel, times within a day, real dates, and at most 24 set times on a channel, listing 48 times in all.
- **The editing page is closed by default and short-lived.** It runs only while its screen is open, after you've turned it on. It refuses connections from outside your home network (anything but private, link-local and loopback addresses), requests for any address but the one shown (so another website can't reach it through your browser), and requests without the six-digit code, which is new each time. Five wrong tries shut a device out, and 20 from anywhere lock the page, so one device can't lock you out and guessing stays hopeless. At most 8 connections at once, each one request, capped at 512 KB and 10 seconds. It's plain http (a browser can't trust a certificate from a TV), so the TV says to use it on a network you trust. The page runs only its own script, shows library names as plain text, and fetches nothing from anywhere else.
- **Sign Out and Delete ask first**, so one stray click, or a button pressed by anything paired with the Apple TV, can't undo your setup.
- **The web version** runs only its own code: its Content Security Policy (`Web/public/_headers`) allows scripts only from gregular.tv, connections only to servers (https, or http that Chrome confines to your home network), no frames but its own channel editor, and, with Trusted Types, no script URLs but hls.js's own workers. Library names are only ever put on the page as text. Every library it uses is served from gregular.tv, never a CDN: hls.js and the WASI shim are in `Web/public/vendor`, unchanged, with their licences.
- **Quick Connect:** approve a code only when your own TV is showing it. Another device can ask Jellyfin for a code while calling itself "Apple TV", and approving its code would sign that device in as you.
