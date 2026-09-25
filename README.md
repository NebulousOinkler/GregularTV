# Gregular TV

*We now return to your Gregular programming.*

A Jellyfin client for Apple TV that plays your library as always-on TV channels. See [PLAN.md](PLAN.md) for the design, and [TODO.md](TODO.md) for planned features (custom channels, fixed-time programmes).

## IMPORTANT NOTE: 
This is mostly AI coded. Why does this exist? I wanted a better shuffle algorithm than what I found in existing applications and I didn't want to make the rest of the bones just to watch videos from a Jellyfin server. I wrote the shuffle algorithm myself in python and had it translated to Swift by the LLM. It's mostly for personal use, but it's open source regardless. Have fun!

## Status

Version 1.0. All seven milestones in [PLAN.md](PLAN.md) are done. The core package handles scheduling, the Jellyfin client and privacy, and the tvOS app has sign-in, live channels, surfing, a six-hour guide, quality settings, and commercial breaks from a Jellyfin library named `Commercials` (see PLAN.md §9a).

Open `App/GregularTV.xcodeproj` in Xcode and run the **GregularTV** scheme on an Apple TV simulator or device. Requires tvOS 17 or later and Jellyfin 10.9 or later.

## Install on an Apple TV

1. In Xcode, select the **GregularTV** target › *Signing & Capabilities*, and choose your **Team**. If Xcode says the bundle identifier is taken, change `dev.gregulartv.GregularTV` to one of your own (for example `com.yourname.gregulartv`).
2. Pair the Apple TV: on the Apple TV, *Settings › Remotes and Devices › Remote App and Devices*; in Xcode, *Window › Devices and Simulators*.
3. Choose the Apple TV as the run destination, set the scheme's *Run* build configuration to **Release** (*Product › Scheme › Edit Scheme*), and press Run. Release builds leave out every debug option.

With a free Apple ID the app has to be reinstalled every 7 days; a paid developer membership makes that a year, and TestFlight works for sharing it.

The project is ready for TestFlight and App Store uploads: it includes Apple's privacy manifest (`App/GregularTV/PrivacyInfo.xcprivacy`: no tracking, no data collected, `UserDefaults` for the app's own settings only, reason CA92.1) and declares that it uses only exempt encryption (`ITSAppUsesNonExemptEncryption = NO`), so App Store Connect doesn't ask about export compliance for each build. In App Store Connect's privacy questions, the matching answer is **Data Not Collected**.

**Signing for upload.** Debug builds sign automatically (Apple Development). Release builds for a real Apple TV sign manually with **Apple Distribution** and the App Store profile named **Gregular TV App Store**, so archiving doesn't need a registered device. To upload: choose **Any tvOS Device (arm64)**, then *Product › Archive*, then *Distribute App › App Store Connect*. Raise the build number for every upload. The profile expires after a year: renew it on developer.apple.com (*Profiles*), download it and double-click it. If you use a different team or profile name, change `PROVISIONING_PROFILE_SPECIFIER` in the target's Release build settings.

## Run the tests

Core logic, on the Mac:

```bash
swift test
```

App-hosted tests (Keychain), on the tvOS simulator:

```bash
xcodebuild test -project App/GregularTV.xcodeproj -scheme GregularTV -destination 'platform=tvOS Simulator,name=GregularTV Tests'
```

Run app tests on a dedicated simulator ("GregularTV Tests"), not the one you're watching. A test run reboots its simulator, which freezes any live view attached to it.

## Schedule code

Every channel's running order comes from one 10-character **schedule code** (like `7KQM2-X9PDA`), shown and editable in Settings (click and hold while watching). The first launch picks a random one. Two Apple TVs with the same code, the same Jellyfin library and the same `channels.json` show the same programmes at the same time on every channel. Changing the code reshuffles everything. See PLAN.md §9b for how the code becomes each channel's derangement.

## Commercials

Every programme starts on the half hour. The time from its end to the next half hour is commercials, from a Jellyfin library named `Commercials` (the name is set in `channels.json`):
- **After a TV episode:** all of it, after the episode.
- **In a film:** a film's leftover can be up to half an hour. Up to 10 minutes goes after the film. More is shared out evenly between the break after it and one or two **mid-roll** breaks inside it (halfway, or at a third and two thirds), each 10 minutes at most: one mid-roll for up to 20 minutes, two beyond that. At least 15 minutes of film plays between breaks, so a short film gets fewer mid-rolls (none under 30 minutes) and the rest goes after it. The film stops at the break and carries on from the same point after it.
- Clips play in the order of the channel's derangement, with the same `a` and `b` as its shows, carrying on from break to break.
- **At most 20 minutes of commercials in one break.** A longer break (after an episode that ends well before the half hour, a short film, or at the end of a day) is blank after that, with the "Up next" card, and the programme still starts on time.
- A gap of a minute or less gets no commercials. When a clip ends, the next only starts if at least half of it will play before the last 15 seconds; otherwise the rest of the break is blank. A clip still playing then is cut off.
- The last 15 seconds of every break are the "Up next" card: the last commercial fades out quickly into it, then the card fades to black and the programme fades in.
- Clips are never re-encoded: one Jellyfin would have to re-encode (for example, a video codec the Apple TV can't play) is skipped, and its time is blank. There's no bitrate cap for commercials, so the quality setting never stops one playing. **MP4, H.264/AAC** plays everywhere; keep the bitrate modest if you watch over a slow remote connection.
- The screen is blank during any unfilled time, with an "Up next" card showing when the next programme starts, or during a film's mid-roll, a "Now playing" card saying when it's back.
- It's always clear when the programme is over: while commercials play, a small **Commercial break · Back at 9:30 PM** badge sits in the top corner (the banner comes and goes as usual). The channel list shows **Up next: …** with **Commercial break · starts 9:30 PM**, and the guide draws each programme's break as a darker tail on its block.
- **Settings › Commercials › Play commercials** turns them off: every break, mid-rolls included, is blank. Programme times don't change, so you stay in step with everyone on the same schedule code.

## Remote controls

**To change what a button does,** edit the tables at the top of `App/GregularTV/Remote/RemoteControls.swift`: one per screen (watching, channel list, guide, Settings), each a list of `button: action`. The hints on screen are written from the same tables. As shipped:

The app starts on the channel you last watched. "Click" means pressing the pad down; "slide" means moving a finger across it; a "light touch" is touching it without clicking. In the Simulator, the arrow keys are clicks on the edge of the pad, Return is a click, the space bar is Play/Pause and Escape is Menu; the Simulator can't slide or touch.

If light touches near the edge of the pad change the channel, set the Apple TV's **Settings › Remotes and Devices › Clickpad** to **Click Only**: with "Click and Touch", tvOS itself turns a touch on the edge into a click there.

| Input | Action |
|---|---|
| Click left / right (edge of the pad) | Channel down / up (the banner previews each channel, and tunes when you stop) |
| Slide left | Channel list; Select tunes. Slide right, Menu, or 15 s idle closes it and stays on the current channel. Play/Pause opens Settings |
| Slide up | Show the info banner, fading in slowly |
| Light touch, or click (centre) | Show the info banner (clock, progress, time in). Again while showing: switch between end time and time left |
| Slide down | Hide the banner at once |
| Menu (or Back ‹) | Programme guide, six hours ahead, scrolling sideways; Select on a programme tunes to its channel, and 60 s idle closes it. In the guide, Menu first moves up to its Settings button (highlighted, not opened), then goes back to the programme. Menu never leaves the app: use the TV (Home) button |
| Click and hold | Settings: streaming quality, trouble with this programme (step down quality, 720p, standard), schedule code, commercials, diagnostics, sign out. In the guide, Play/Pause also opens Settings. Close with Menu, Play/Pause or Done |
| Play/Pause | Pause; press again to jump back to live |
| Digits (keyboard only) | Type a channel number |

## Debug options

Debug builds accept launch arguments. Release builds leave them out entirely.

| Argument | Effect |
|---|---|
| `-handoffTest` | Shifts every channel so the current programme ends about 50 s after launch, to test the hand-off to the next programme quickly. |
| `-openChannelList` | Opens the channel list on launch, to check its focus handling without arrow keys. |
| `-openGuide` | Opens the guide on launch, to check it without a Menu button. |
| `-pretendCommercials` | Uses a dozen library videos, cut to 30–120 s, as commercials, to test breaks without a `Commercials` library. |

```bash
xcrun simctl launch booted dev.gregulartv.GregularTV -handoffTest
```

**Playback diagnostics** are a setting, not a build type: turn on **Show playback diagnostics** in Settings (click and hold while watching) to add a technical line to the banner. It shows quality, whether the server is transcoding and why, buffering, and how far behind live playback is. It's off by default. It never shows the server address, token, user or stream URLs.

**When Jellyfin can't re-encode fast enough** (a slow server converting a file the Apple TV can't play as-is), a programme that fails or stalls is retried with less work: 720p, then a step lower on each further failure, for that programme only (Settings shows it as the programme's fix). A programme Jellyfin would re-encode isn't started with under 3 minutes left; the screen shows "Up next" instead, so the server isn't asked for an expensive transcode for a minute of video.

## Where to edit things

| I want to… | Edit |
|---|---|
| Change the channel line-up | `Sources/GregularTVCore/Resources/channels.json`, then run `swift test` to validate it |
| Add a shuffle/scheduling algorithm | New file in `Sources/GregularTVCore/Scheduling/Strategies/`, then add it to `StrategyRegistry.all` |
| Add a way to choose channel content | New type in `Sources/GregularTVCore/Channels/Sources/`, then add it to `ChannelSourceRegistry.all` |
| Change the order commercials play in | New `GapFiller` in `Sources/GregularTVCore/Scheduling/GapFiller.swift`, then add it to `GapFillerRegistry.all` and set `"filler"` in `channels.json` (see PLAN.md §9a) |
| Change what the remote's buttons do | The tables at the top of `App/GregularTV/Remote/RemoteControls.swift` (one per screen) |
| Change how long a mid-roll may be, how many a film gets, or the Up next lead | `ChannelSchedule.longestMidRoll`, `maxMidRolls` and `upNextLead` in `Sources/GregularTVCore/Scheduling/ScheduleEngine.swift` |
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
- **Randomness:** use only the `rng` you're given, or `LazyPermutation` with `content.seed`. `SeededRandom` is deliberately *not* a `RandomNumberGenerator`, because the standard library's shuffle can change between Swift releases.

`StrategyConformanceTests` checks all of this for every registered strategy automatically.

## Privacy

Gregular TV is built to know as little as possible about your Jellyfin server, and to keep even less.

**Stored on the Apple TV (and nothing else):**

| What | Where | Why |
|---|---|---|
| Server address, access token, user ID | Keychain, this device only (excluded from backups and iCloud) | To reconnect without signing in again |
| A random device ID | Keychain, this device only | Jellyfin requires one; it's kept across sign-outs so your device list doesn't fill up |
| Last channel number, streaming quality, schedule code, diagnostics and commercials switches | App preferences | Client settings; no server data |

**Never stored:** your password (it's used for one sign-in request only), your library (titles, episodes, artwork), schedules, watch history, or logs. The library is fetched into memory at launch and is gone when the app quits. Schedules are recomputed from each channel's seed and the clock, so there's nothing to save.

**Never sent to Jellyfin:** what you're watching. The app makes no playback-reporting calls, so nothing appears under "Now Playing" and your watched status and resume points are untouched. The app also refuses remote control from other Jellyfin clients.

**What Jellyfin can still see:** a sign-in in its activity log, this Apple TV (named just "Apple TV") in its device list, and the stream requests themselves, as for any client.

**Enforced, not just promised:**
- **Network:** all requests go through one ephemeral `URLSession`, with no disk cache and no cookies.
- **Privacy check:** [`scripts/privacy-check.sh`](scripts/privacy-check.sh) fails the app build, and `swift test`, if code outside the three allowed files uses anything that persists or leaks data. That covers `UserDefaults`, files, Core Data and SwiftData, caches, cookies, the Keychain, iCloud storage, and system logging (`Logger`, `os_log`, `NSLog`, `print`).
- **Tests:** they check that no playback-reporting endpoint is ever called, that sign-out clears credentials even when the server is unreachable, and that preferences hold only the five client settings.
- **No third-party code:** no analytics or crash reporting, only Apple frameworks. The app sends Apple nothing itself; only tvOS's own *Share Analytics* setting (the device owner's choice) sends crash reports.
- **Privacy manifest:** `PrivacyInfo.xcprivacy` declares the same to Apple: no tracking, no data collected.
- **Artwork:** the app icon and Top Shelf image are drawn by [`scripts/make-artwork.swift`](scripts/make-artwork.swift), never taken from your server.
