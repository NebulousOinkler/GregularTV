# Gregular TV (Jellyfin linear TV for tvOS): Build Plan

A tvOS app that turns a Jellyfin library into always-on "channels". You tune in the way you would with cable: a show is already playing, it's partway through, and a guide shows what's on now and next.

## 1. Goals and non-goals

**Goals**
- Channels that act like broadcast TV. Tuning in joins the current programme at the correct offset.
- A channel selector (up/down surfing, number entry) and an EPG-style schedule grid.
- **Privacy by construction.** The app keeps nothing about the server except what it needs to stream video.
- **Easy to edit.** Adding a new shuffle or scheduling algorithm means adding one file and one registry line.

**Non-goals (v1)**
- Browsing the library, search, or on-demand playback.
- Live TV or DVR passthrough from Jellyfin's Live TV feature.
- Multi-user profiles, or watch-history sync.

## 2. Core idea: the schedule is a pure function, worked out lazily

We don't store a schedule anywhere, and we never build a channel's whole schedule either. The app works out only the part it needs:

```
run(r)     = pull programmes from strategy.programmes(content, startingAt: ≈r × perRun, rng: seed+r)
             and play them back to back until the next one wouldn't fit in run r (a day)
nowPlaying = walk run((now - epoch) / runLength) from its start to the slot that contains now
```

- `items` is the channel's episodes and movies. They come from Jellyfin at launch and are **kept in memory only**.
- `seed` is a fixed number in the channel definition. Every launch gives the same line-up, like a real channel, with nothing persisted.
- `epoch` is a fixed reference date (2024-01-01 00:00 UTC). Time since the epoch picks the run, then the programme within it.
- A **strategy is an endless generator** (like a Python generator): the engine pulls at most a day of programmes to reach any moment. It never asks for the whole list. So channels can hold any number of items, and there can be any number of channels.
- Each run depends only on the seed and its number, so any moment can be looked up directly, without replaying the schedule from the epoch.

This design is what makes the privacy requirement cheap to meet. No schedule or library data is persisted, because none needs to be. Two Apple TVs with the same channel config show the same thing at the same moment.

## 3. Privacy rules (enforced in code, not by convention)

| Data | Where it lives | Why it's allowed |
|---|---|---|
| Server URL | Keychain | Needed to reach the server |
| Access token + user ID | Keychain | Needed to authenticate, and for Jellyfin's per-user item and playback queries |
| Device ID (random UUID, made by the app) | Keychain | Jellyfin requires a stable device ID in the auth header |
| Channel definitions (rules, seed, name) | App config (bundled JSON / Swift) | Client-side config, no library content |
| Client settings: last channel **number**, streaming quality, schedule code, diagnostics and commercials switches | `UserDefaults`, through `AppPreferences` only | Client-side preferences; they hold no server data |
| Custom channels, as their channel codes (name, number, rule) | `UserDefaults`, through `AppPreferences` only | Client configuration the viewer typed or picked (decided 2026-09-28, option (a) of the old TODO): a rule may name a genre, series or tag, and nothing else from the library is kept |
| Set times, as their set-times codes (channel number, time zone, series or film names, times, days) | `UserDefaults`, through `AppPreferences` only | The same option (a): only the names the viewer picked |
| Library metadata (titles, IDs, durations, artwork) | **RAM only**, gone on app exit | Needed to build the schedule and guide |
| Password | **Never stored** | Only sent once to get a token (or use Quick Connect instead) |

Enforcement:
- **One network gateway (`JellyfinClient`)** built on `URLSessionConfiguration.ephemeral` with `urlCache = nil`, so nothing is cached to disk. The app loads no images from the server at all; its artwork is drawn by the app.
- **No `UserDefaults`, Core Data, SwiftData, or file writes** outside two allowlisted files: `SecureStore.swift` (Keychain) and `AppPreferences.swift` (the client settings and custom channels above). A build-phase script fails the build if these APIs appear anywhere else.
- **No third-party SDKs**: no analytics or crash reporters. Everything uses Apple frameworks, with no external dependencies.
- **Apple privacy manifest** (`App/GregularTV/PrivacyInfo.xcprivacy`): no tracking, no collected data types, and `UserDefaults` with reason CA92.1 (the app's own settings). The Info.plist sets `ITSAppUsesNonExemptEncryption = NO` (standard HTTPS only).
- **No playback reporting.** The app never calls `/Sessions/Playing`, `/Sessions/Playing/Progress`, `/Sessions/Playing/Stopped` or `/UserPlayedItems`. There's no toggle, so the code path doesn't exist. As a result, nothing shows as "Now Playing", and watched status and resume points on the server stay untouched.
  - **Limits of "invisible":** Jellyfin always records a login in its activity log, and shows an authenticated device under *Devices*. Those are server-side, and no client can avoid them. While a transcode is running, the server also does the work, but without playback reports the dashboard can't link it to a "Now Playing" card.
  - The app sends `/Sessions/Capabilities` with `SupportsMediaControl=false` and no supported commands, so other clients can't remote-control it.
- **Logout** wipes the Keychain entries and drops the in-memory library.

Security (untrusted input, checked 2026-09-29):
- **Redirects** are followed only on the same server: the same scheme, host and port, or `http` up to `https` on the same host (`RedirectGuard`). URLSession drops `Authorization` on a cross-host redirect by itself, but it sends the body again, so a sign-in's password would follow a 307 to another host.
- **Server replies:** the claimed item total is capped (`LibraryQuery.mostItems`), paging stops at an empty page, and each page counts for at most `pageSize` items, so a false total can't plan billions of pages and crash every launch. Every reply is gathered as it arrives and stopped past `URLSessionTransport.largestResponse` (16 MB; the speed test is 3 MB), or turned down at once if it announces more (`BoundedLoad`), so no single reply can fill the app's memory. Server IDs go into URL paths, where they're percent-encoded: they can't change the host or add a query. `TranscodingUrl` keeps only its path and query. The `Authorization` header drops quotes, commas and control characters.
- **Codes** (channel and set-times) are unauthenticated: the CRC-8 only catches typos. `FixedTimesAreValid` checks set times from a code like any others: times within a day, real dates, and at most `FixedProgramme.mostPerChannel` (24) set times listing `mostTimesPerChannel` (48) times in all per channel, which keeps placing them to a few milliseconds.
- **Device type** is trusted nowhere: the app reads no other device's name, and Jellyfin authorises by token, not by name. The device name sent is the kind of device, from the app (`AppModel.deviceName`).
- **Sign Out and deletes** ask for confirmation (`SettingsRows.confirmedRow`).

## 4. Architecture

Four parts, each depending only on the ones before it. The first three are a Swift package, so they're testable with `swift test` on the Mac, without a simulator; only the fourth is Apple TV.

```
jellyfin_tv/
├─ Package.swift                    # GregularCore, GregularJellyfin (tvOS 17+, macOS for tests)
├─ Sources/GregularCore/            # 1. THE LOGIC: Foundation only
│  ├─ Model/                        # MediaItem, Channel, Airing (+ Tuning, Onscreen), FixedProgramme
│  ├─ Services/MediaServices.swift  # what a media server must provide: MediaLibrary, StreamSource,
│  │                                # MediaStream, MediaServiceFailure
│  ├─ Rules/                        # ScheduleRules: the one registry of special rules (§9c), by kind:
│  │                                # sequence (not twice in a row), pins (set times), covers, checks
│  ├─ Scheduling/
│  │  ├─ ScheduleEngine.swift       # ChannelSchedule: the shared schedule's runs, joins, slots, breaks, mid-rolls, tune(at:)
│  │  ├─ ScheduleEngine+SetTimes.swift # set times laid over the shared schedule: windows, cuts, covering
│  │  ├─ ScheduleStrategy.swift     # protocol (see §5)
│  │  ├─ StrategyRegistry.swift     # the one list of programme strategies
│  │  ├─ Strategies/                # ShuffledShows (default), RandomShuffle, SequentialBySeries,
│  │  │                             # SeriesRoundRobin, ShuffledSeriesInOrder
│  │  ├─ GapFiller.swift            # commercial order: protocol, registry, shuffle / none
│  │  ├─ ChannelContent.swift       # a channel's programmes, grouped and sorted
│  │  ├─ LazyDerangement.swift      # (a·x + b) mod p, from random_derangement.py (unused, for reference)
│  │  ├─ LazyPermutation.swift      # 12-round Feistel shuffle, readable at any position
│  │  ├─ ShuffledOrder.swift        # every shuffle: Fisher–Yates up to 10 items, Feistel above; Passes
│  │  ├─ ScheduleCode.swift         # the shared 10-character code → per-channel keys
│  │  └─ SeededRandom.swift         # SplitMix64: deterministic, portable RNG
│  ├─ Channels/
│  │  ├─ ChannelLineup.swift        # loads channels.json, adds custom channels, builds every schedule
│  │  ├─ CustomChannel.swift        # channels made in Settings, and their channel codes
│  │  ├─ Crockford.swift            # the typing-friendly alphabet of schedule and channel codes
│  │  ├─ ChannelSource.swift        # protocol + registry: what goes on a channel
│  │  ├─ Sources/BasicSources.swift # all, genre, series, years, tag
│  │  └─ ChannelNavigator.swift     # channel up/down, typed numbers
│  ├─ Guide/GuideWindow.swift       # the guide's time window and cells
│  ├─ Playback/StreamingQuality.swift  # quality caps, Auto's bitrate rule, step-down ladder
│  ├─ Preferences/AppPreferences.swift # the only UserDefaults: client settings and custom channel codes
│  └─ Resources/channels.json       # the channel line-up
├─ Sources/GregularJellyfin/        # 2. THE JELLYFIN CONNECTION: Foundation, GregularCore, Security
│  ├─ HTTPTransport.swift           # the ONLY real network path (ephemeral, no cache/cookies)
│  ├─ JellyfinAPI.swift             # request building, auth header, JellyfinError
│  ├─ JellyfinServer.swift          # pre-login: server check, Quick Connect, password → Credentials
│  ├─ JellyfinClient.swift          # signed in: libraries, playback sources, speed test, stop transcode,
│  │                                # sign out; conforms to MediaLibrary and StreamSource
│  ├─ LibraryQuery.swift            # paged /Items → [MediaItem] (Jellyfin types → MediaItem.Kind)
│  ├─ Playback.swift                # DeviceProfile, PlaybackSource (→ MediaStream)
│  ├─ SecureStore.swift             # Credentials, Keychain (server, token, user ID, device ID)
│  └─ ServerAddress.swift, ClientIdentity.swift, JellyfinJSON.swift
├─ Sources/GregularScreens/         # 3. WHAT THE SCREENS DO, not how they're drawn: Foundation, Observation,
│  │                                #    GregularCore (and GregularJellyfin, for sign-in only)
│  ├─ App/                          # AppModel (signed out / loading / watching), LoginModel, FriendlyError,
│  │                                # DebugOptions, DemoCredentials
│  ├─ Player/
│  │  ├─ PlayerDeck.swift           # the ONLY way to actual video: a queue player with its own picture
│  │  ├─ ChannelPlayer.swift        # every playback decision: tuning, hand-offs, breaks, retries, head
│  │  │                             # starts, quality; plays on two PlayerDecks
│  │  └─ ChannelSurfer.swift        # channel up/down with preview, typed numbers, the list
│  ├─ Channels/ChannelEditorModel.swift  # making and editing a custom channel, with its preview
│  ├─ Watch/WatchModel.swift        # the watch screen's rules: banner, overlays, curtain, remote actions,
│  │                                # and the words on the banner, cards and badge
│  ├─ Remote/RemoteControls.swift   # the button tables (one per screen) and hints
│  └─ Text/                         # displayTitle / displaySubtitle, quality labels, break wording
├─ Tests/GregularCoreTests/         # schedule, strategies, commercials, guide, privacy, layers
├─ Tests/GregularJellyfinTests/     # Jellyfin client and sign-in (against a mock server), privacy
├─ Tests/GregularScreensTests/      # player and watch screen on fake decks: no video, no Apple TV
├─ scripts/                         # privacy-check.sh (runs in the build), layer-check.sh, make-artwork.swift
└─ App/ (Xcode tvOS target "GregularTV", shown as Gregular TV)   # 4. APPLE TV: SwiftUI, AVFoundation, UIKit
   ├─ GregularTVApp.swift, RootView.swift, DemoMode.swift   # launch; AppModel with AVFoundation decks
   ├─ Login/          LoginView (draws LoginModel)
   ├─ Player/         WatchView (draws WatchModel), AVPlayerDeck (PlayerDeck on AVQueuePlayer),
   │                  VideoSurface, ChannelListView, SettingsView, ChannelEditorView, SettingsRows, BreakStyle
   ├─ Remote/         RemoteControls+SwiftUI (attaches the tables), RemoteGestures (clicks, slides, touches)
   ├─ Guide/          GuideView (scrolling EPG grid)
   └─ GregularTVTests/  app-hosted tests (Keychain, player on AVFoundation, commercials, surfing, remote)
```

**Dependencies.** `GregularJellyfin → GregularCore`; `GregularScreens → both`; the Apple TV app → `GregularScreens` and `GregularCore`, never Jellyfin. The logic knows nothing about Jellyfin, networking, AVFoundation or UI: it defines what it needs from a server (`MediaLibrary` for programmes and commercials, `StreamSource` for playable streams and the speed test) and works with any implementation. `GregularScreens` knows what the screens do but not how they're drawn or how video plays: `ChannelPlayer` reaches video only through `PlayerDeck`, and only `AppModel`, `LoginModel` and `DemoCredentials` know the server is Jellyfin. The Apple TV app only draws the models, provides `AVPlayerDeck`, and connects the Siri Remote. `scripts/layer-check.sh` enforces all of this, and runs as a test. Inside the logic, `Scheduling` knows nothing about where items come from; strategies only see `[MediaItem]` and an RNG.

**A web version.** It would keep the first three parts as they are (the same channels, schedules, banner rules, remote tables and words) and bring its own views that draw `AppModel`, `LoginModel` and `WatchModel`, its own `PlayerDeck` on `<video>` elements, and its own input (keyboard or a remote) connected to `RemoteControls`. `Tests/GregularScreensTests` already runs the player and the watch screen on a fake deck, the same way. (How the Swift runs on the web, such as WebAssembly or a server, is still to decide.)

**Reusing it, for example for radio.** A radio app would keep `GregularCore` (channels, shuffles, commercials, the guide maths) and `GregularJellyfin`, add music kinds to `MediaItem.Kind` and map Jellyfin's audio types to them in `LibraryQuery`, and bring its own player and screens, which would use `StreamSource` exactly as `ChannelPlayer` does.

## 5. The extension point: schedule strategies

This is the most important interface for editing the app later. It's small on purpose:

```swift
public protocol ScheduleStrategy {
    static var id: String { get }             // referenced by channels.json, e.g. "random-shuffle"
    static var displayName: String { get }
    static var mayReorderToFit: Bool { get }  // default true; false when order matters
    init()

    /// An endless stream of programmes, like a Python generator.
    func programmes(from content: ChannelContent,
                    startingAt position: Int,
                    rng: SeededRandom) -> AnyIterator<MediaItem>
}
```

- `content` is the channel's programmes in a fixed order (`items`), also grouped by series (`series`), plus the channel's `seed`.
- `position` is roughly how many programmes have aired before this run. Strategies that continue a sequence start from it.
- `rng` is seeded for the run.

An example strategy, and the whole file it lives in:

```swift
/// Series take turns: an episode of show A, then B, then C, then back to A.
struct SeriesRoundRobin: ScheduleStrategy {
    static let id = "series-round-robin"
    static let displayName = "Series Round Robin"
    static let mayReorderToFit = false   // skipping would break the turn order

    func programmes(from content: ChannelContent, startingAt position: Int, rng: SeededRandom) -> AnyIterator<MediaItem> {
        let shows = content.series
        let turnOrder = LazyPermutation(count: shows.count, seed: content.seed)
        var position = position
        return AnyIterator {
            defer { position += 1 }
            let round = ChannelContent.pass(position, shows.count)
            let show = shows[turnOrder.index(at: position)]
            return show[ChannelContent.wrap(round, show.count)]
        }
    }
}
```

`ShuffledOrder` reads position N of a shuffled order: Fisher–Yates for up to 10 items, and above that `LazyPermutation`, which doesn't build the order (a Feistel network with cycle-walking). That's how Random Shuffle plays every item once before repeating, across thousands of items, while computing only what's about to air.

The registry is one list (`StrategyRegistry.all`).

**To add an algorithm:** create a file in `Strategies/`, conform to the protocol, and add one line to the registry. A shared test suite runs against every registered strategy automatically. It checks that the stream never ends, is deterministic, only uses the channel's items, doesn't depend on the input order, and handles a single item. New strategies get that coverage without writing any tests.

`ChannelSource` and `GapFiller` work the same way: a protocol with a registry.

### Future hook: time-of-day programming
A second, optional protocol, `DaypartStrategy`, can wrap strategies ("cartoons 7–10am, movies after 8pm"). It isn't in v1, but `ChannelSchedule` asks for "the airing at time T" instead of assuming one flat list, so adding dayparts later doesn't need a rewrite.

## 6. Schedule engine math

- **Runs:**
  - Time from the epoch is cut into runs of a day (longer only if one programme is longer than a day), rounded up to 30 min.
  - Each run pulls programmes from its own stream and plays them **back to back**; a programme never waits for a boundary. (Until 2026-09-23 runs were split into 2-hour-plus blocks that programmes couldn't cross, which left movie channels with up to two hours of dead air after a film.)
  - Near the end of a run, strategies with `mayReorderToFit` may pass over up to 15 programmes that wouldn't finish in time, to find one that does.
- **Leftover time:** time left at the end of a run (once a day) joins the last slot, like padding. It's filled with commercials up to the next programme, at most 20 minutes of them (`longestCommercialRun`); any more is blank, with the "Up next" card.
- **Continuity:** run `r` starts the strategy at position `⌊r × runLength / averageSlot⌋`, an estimate of how many programmes aired before. A sequence may repeat or skip an item where runs meet, once a day. That's the price of never building or replaying the full schedule.
- **Lookups:**
  - `tune(at:)`, `programme(at:)` and `commercialBreak(at:)` walk from the start of the run: at most a day of programmes, whatever the library size (tested with a 20,000-episode channel).
  - `airings(from:to:)` walks forward slot by slot, across runs.
- **Padding:** optionally rounds each slot up to the next 5/15/30-minute boundary.
- **Runtime:** items with no or zero runtime are filtered out when loading.

## 7. Jellyfin integration

- **Auth:** Quick Connect is the main method, because typing on a TV is painful. The fallback is `POST /Users/AuthenticateByName`. Every request sends the header `Authorization: MediaBrowser Client="Gregular TV", Device="Apple TV", DeviceId="<uuid>", Version="x", Token="<token>"`.
- **Items:** `GET /Items?Recursive=true&IncludeItemTypes=Episode,Movie&Fields=…` with only the fields we need (`RunTimeTicks`, `SeriesId`, `SeriesName`, `ParentIndexNumber`, `IndexNumber`, `Name`, `ImageTags`). Results are paged.
- **Playback:** `POST /Items/{id}/PlaybackInfo` with a tvOS `DeviceProfile` (direct-play HEVC/H.264 + AAC/AC3/EAC3 in MP4/MOV/HLS, and transcode everything else to HLS). Then:
  - Direct play: `/Videos/{id}/stream.{container}?Static=true…`.
  - Otherwise: Jellyfin's `TranscodingUrl` (HLS: a remux or a transcode).
  - Either way, the player seeks to the live offset itself. Jellyfin's HLS transcoder restarts at the segment requested.
  - Stream URLs carry the token as `ApiKey`, the same as every Jellyfin client, because AVPlayer can't reliably send headers on segment requests.
  - **Subtitles are off in v1.** Otherwise Jellyfin burns in each file's default subtitle track, which forces a full video transcode that a Raspberry Pi can't sustain. Jellyfin 10.11 ignored `SubtitleStreamIndex=-1` on its own (the live test still showed `SubtitleCodecNotSupported`). The fix that works is declaring every subtitle format as `External` in the `DeviceProfile`, so Jellyfin never needs to burn them in. Later, subtitles can come as WebVTT inside HLS (`SubtitleProfile` method `Hls`), which doesn't need a video transcode.
  - When leaving an item, `DELETE /Videos/ActiveEncodings` stops the transcode right away. This is resource cleanup, not playback reporting.
- **Seamless next programme:** 30 seconds before an item ends, prepare the next item in an `AVQueuePlayer`, so the hand-off doesn't show a loading spinner.
- **Pause and jump to live:** Play/Pause really pauses, and the banner shows `PAUSED · live is +mm:ss ahead` while it's paused. Pressing Play again **jumps back to live**: it recomputes `nowPlaying` for the current time and tunes to it, even if a different programme is on by then. There's no DVR-style resume from the paused point. That keeps the channel honest, and we don't need to store anything.
- **The stream only restarts on an explicit change:**
  - **What restarts it:** a different channel, a different quality, a new schedule code, or resuming from pause (which jumps to live). Also recovery: a failed load, a 30-second stall, or falling more than 60 s behind live.
  - **Head start for re-encoding:** tuning into a programme Jellyfin has to re-encode (`PlaybackSource.reencodesVideo`), the player seeks 20 s past live, buffers paused with a blank screen ("Getting this ready · starts in N s"), and plays when live reaches that point. Each failure on the channel doubles it, up to 2 minutes; changing channel resets it, and the retry wait. It helps when the transcode is slow to start or roughly real-time; a server that converts well below real time will still stall eventually. Checked live on 2026-09-23: a *Guardian* episode that stalled every time played after a 20 s head start.
  - **Re-encoding that can't keep up:** when a re-encoded programme fails or stalls, the retry asks for 720p, then one step lower on each further failure (4 → 1.5 Mbps), for that programme only, through the programme fix (so Settings shows it). The server's processor is the bottleneck, so Auto doesn't re-measure the connection first. A stream that fails during a head start is retried at once, not after the head start.
  - **Too little left:** a programme Jellyfin would re-encode isn't started with under 3 minutes (`minReencodedTimeLeft`) to go; the screen is blank with "Up next" until the break after it, or the next programme.
  - **"Trouble with this programme?"** (Settings, while a programme is on): *Step Down Quality* restarts it one step lower on the fixed ladder (20 → 10 → 4 → 1.5 Mbps) and steps down again after 4 s of buffering; *Play at 720p* restarts it at 4 Mbps; *Standard* goes back. In memory only, for that programme: changing channel, changing quality, or the next programme starting clears it. The programme loaded behind a break, and commercials, always use the standard rules.
  - **What never does:** opening or closing the guide, channel list, Settings or banner; choosing the channel or quality that's already selected; toggling diagnostics; or the app briefly becoming inactive (Control Center, a notification). `start()` does nothing when already playing, and only a real trip to the background stops the player.
  - **Tests:** `StreamStabilityTests` counts re-tunes to check this.
- **Drift correction:** coming back to the foreground or switching channels uses the same "tune to live" path, so it's one code path for every case.

## 8. UI (SwiftUI on tvOS)

- **Launch:** first run shows the login screen. After that, it goes straight to the last-watched channel, stored as a number in `AppPreferences`. If that channel no longer exists or is empty, it falls back to the lowest-numbered channel that has content.
- **Watching:** full-screen player. Click the left or right edge of the pad to change channel. A light touch shows a banner: channel number and name, title, S/E, progress bar, and the clock. Every button's job is set in one table per screen (`Sources/GregularScreens/Remote/RemoteControls.swift`); README has the current layout.
- **Guide:** press Menu to open an EPG grid. Channels are the rows and time runs left to right, from the current half hour to at least 6 hours ahead (6.5 hours); 3 hours fit on screen and the grid scrolls sideways as focus moves, with channel names pinned on the left and times pinned along the top. Focus moves across programmes, and Select tunes in. The data comes from `ChannelSchedule.programmes(from:to:)`, one block per programme (a film's mid-roll breaks inside it).
- **Channel list:** a compact vertical list, the classic "channel selector", overlaid on the video.
- Artwork loads lazily into the in-memory cache only.

## 9. Channel configuration

v1: a bundled `Resources/channels.json` that users edit by hand and then rebuild. It **ships with a default line-up** built only from generic rules, so it works on any library without editing.

**Rules that apply to every channel:**
- If a channel's rule matches no items in your library, the channel is **hidden automatically** and doesn't show as a dead channel. So the defaults can include many genres, and you only see the ones your library supports.
- A genre rule can list alternatives, such as `["Science Fiction", "Sci-Fi", "Sci-Fi & Fantasy"]`, because metadata providers name genres differently.
- Channel numbers are fixed by config, so hidden channels leave gaps, like real TV. The surfer skips the gaps.

**Default line-up:**

Every default channel uses the `shuffled-shows` strategy, the `shuffle` commercials and 30-minute slots (`padTo`), each with its own seed:

| # | Name | Source rule |
|---|---|---|
| 1 | All TV | every Episode |
| 2 | Comedy | Episodes, genre Comedy/Sitcom |
| 3 | Drama | Episodes, genre Drama |
| 4 | Animation | Episodes + Movies, genre Animation |
| 5 | Sci-Fi | Episodes, genre Science Fiction/Sci-Fi/Sci-Fi & Fantasy |
| 6 | Kids & Family | Episodes + Movies, genre Family/Kids/Children |
| 7 | Documentary | Episodes + Movies, genre Documentary |
| 8 | Reality | Episodes, genre Reality |
| 10 | Movies | every Movie |
| 11 | Action Movies | Movies, genre Action/Adventure |
| 12 | Comedy Movies | Movies, genre Comedy |
| 13 | Horror & Thriller | Movies, genre Horror/Thriller |
| 14 | Classics | Movies, production year < 1980 |

Source types available: `all`, `genre`, `series`, `years`, `tag` (all matched case-insensitively by name). A channel's optional `itemTypes` narrows any source to `Episode` or `Movie`. The config format looks like this:

```json
[
  { "number": 2, "name": "Sitcoms", "itemTypes": ["Episode"],
    "source": { "type": "genre", "anyOf": ["Comedy", "Sitcom"] },
    "strategy": "series-round-robin", "seed": 42 },
  { "number": 10, "name": "Movies", "itemTypes": ["Movie"],
    "source": { "type": "all" },
    "strategy": "random-shuffle", "seed": 7, "padTo": 30 },
  { "number": 20, "name": "Star Trek",
    "source": { "type": "series", "anyOf": ["Star Trek: The Next Generation", "Star Trek: Deep Space Nine"] },
    "strategy": "sequential-by-series", "seed": 1 }
]
```

A test loads the bundled `channels.json` and checks every entry: each `strategy` ID exists in the registry, each `source` type is known, channel numbers are unique, and the `ChannelRule`s pass (§9c). A typo in a hand edit then fails `swift test` rather than showing up as an empty channel on the TV.

Sources refer to things by **name or rule**, never by Jellyfin item ID. That keeps server identifiers out of config. The names are resolved to items in memory at launch.

Channels can also be made on the Apple TV, in Settings (custom channels, §9c).

## 9b. Shuffled Shows strategy and the schedule code

**The shuffle (`ShuffledOrder`):** a shuffled order of `0..<N`, readable at any position.
- **Up to 10 items:** a seeded Fisher–Yates shuffle, worked out in full. Every order is exactly as likely.
- **More than 10:** `LazyPermutation`, a 12-round Feistel network with cycle-walking, which reads any position without building the order.
- **`ShuffledOrder.Passes`:** a new shuffle for each pass through the items (pass `⌊position / N⌋`), seeded by the key and the pass number. If a pass would open with the item that closed the pass before, its first two swap, so nothing plays twice in a row. With two items that leaves one order, used every pass.

**Why it replaced the derangement (2026-09-28):** the first version ported `random_derangement.py` as `LazyDerangement`: step through `(a·x + b) mod p` for a prime `p > N`, keeping values below `N`. Testing it with many codes showed:
- `b` only moves the starting point, so a channel had just `p − 1` different show loops (12 on a 12-show channel), whatever the code.
- Each order steps by a fixed amount, so the first two shows almost decide the rest; some codes gave plain title order, and show 0 almost never came first.
- Commercials reused the shows' `a` and `b`, so their order was a slow climb through the pool.

A Feistel network has none of those limits, but with 4 rounds it was uneven over small domains, so it now has 12 rounds, and channels of 10 or fewer use Fisher–Yates, which is exact. After the change every tested size matched a perfect shuffle: every order of up to 9 items appears equally often, items land evenly across positions, and 20 million codes gave the number of distinct 12-show loops a perfect shuffle would. With 40 or more shows the limit is the code itself: 2⁵⁰ different schedules per channel. `LazyDerangement` and `Primes` are kept, unused, for reference.

**How it's used (`ShuffledShows`, id `shuffled-shows`; every default channel uses it):**
- **Show IDs:** each show or movie on a channel gets a numeric ID, its index among the channel's series sorted by title.
- **Order:** each pass plays every show once, in that pass's shuffle. On pass `k`, a show plays its episode `k`, wrapping round, so each show advances one episode per pass.
- **Episodes only go forwards within a run.** The one exception: after a show's final episode, its next appearance cycles back to the pilot (its first available episode). Movies are exempt.
- **Spacing:** a show's next episode comes after N shows on average, and at least one other show in between.
- **Other strategies:** Random Shuffle uses `ShuffledOrder.Passes` over every item; Series Round Robin uses one `ShuffledOrder` for its fixed turn order.

**The schedule code (`ScheduleCode`):**
- **Format:** 10 Crockford base32 characters (`XXXXX-XXXXX`, 50 bits). It's shown and editable in Settings; the first launch picks a random one.
- **How it becomes each channel's shuffle:**
  1. `code ↔ value` is one-to-one.
  2. `value` + the channel's seed from `channels.json` gives a per-channel key, the intermediate integer (SplitMix64 mixing).
  3. The key seeds the channel's `ShuffledOrder.Passes` (and every other random choice on the channel).
- **Scope:** one code drives every channel, and every other random choice (other strategies, commercial breaks) too.
- **Sharing:** two Apple TVs with the same code, library and `channels.json` show the same programmes at the same time. That was checked on the simulator: the same code gave an identical guide across relaunches, and a different code a different one.

**Runs:** each run of about 24 hours is filled back to back from one stream, so nothing repeats or is skipped within a run. Looking up a moment fills at most one run, about a day of programmes, whatever the library size. Where runs meet, once a day, one programme may repeat or be skipped.

## 9c. Special rules, set times and custom channels (built 2026-09-28)

**The rules registry.** `ScheduleRules.all` (`Sources/GregularCore/Rules/`) lists every rule that must hold whatever a channel's strategy. Each rule is one of a few kinds, and the engine or the line-up asks the registry for the kind it needs:

| Rule | Kind | What it guarantees |
|---|---|---|
| `NoProgrammeTwiceInARow` | sequence (programmes) | The same movie, or the same episode, never airs twice in a row. A show may follow itself with its next episode. |
| `NoCommercialTwiceInARow` | sequence (commercials) | The same commercial never plays twice in a row. |
| `PinnedProgrammes` | pin | Set times air at exactly their local times, over the shared schedule; a series plays its next episode at each airing. |
| `ExclusiveProgrammesOnlyAtSetTimes` | cover | A set programme marked `exclusive` only airs at its set times: its other airings get a stand-in. |
| `FixedTimesAreValid` | channel check | Set times need a time zone, and no two may share a time on a day they both air. |
| `CustomChannelNumbers` | line-up check | Custom channels use 20 to 99, and no two channels share a number. |
| `SetTimesNeedTheirChannel` | line-up check | Set times belong to a channel in the line-up, one set per channel. |

**How the sequence rules are kept.** Streams go through `RuledStream`: an item a rule rejects waits and airs as soon as it may, so nothing is dropped and the order moves as little as possible. Three places need more than that, and each is handled without chaining one run to the next:
- **Where runs meet.** Each run is laid out on its own; only its *join* depends on the run before, and never changes what it takes from the strategy. If the run's first programme mustn't follow the last one before it, a programme the rules allow takes its slot; failing that, the first slots are left out until one may follow, and their time is a break after the last programme. So every walk (from any starting run) gives the same schedule.
- **Next to a set time.** The shared schedule's programme just before a set time, or still on after it, is swapped for a stand-in that fits its slot if the rules don't allow it next to the set programme. If none fits, that part of it becomes a break instead. Only that slot changes.
- **Set times themselves.** A set time is left out that day if it would overlap the one before it, or if it's the same programme straight after it. Two set times of the same film close together are the viewer's choice, and may air with only a break between.
A channel whose shuffle has only one programme can't avoid repeating it: there, the rules give way.

**Programmes at set times: an overlay (changed 2026-09-28).** Set times name series or items and local times, with optional `days` (weekdays or dates) and `exclusive`, each read in its own time zone. They come from a channel's `fixed` list in `channels.json` (with the channel's `timeZone`), or from a household's `SetTimes`, made in Settings › Set times for any channel.

The first version wove set times into the schedule: runs became local days and each set time a hard edge. That moved everything around it, so two households sharing a schedule code, one with a set time, agreed on only about 11% of moments (0% with `exclusive`). Now there are two layers:
- The **shared schedule** comes from the code and the channel alone, in uniform runs, exactly as without set times.
- Each set time is a **window**, from its time to the end of its programme's slot. Inside it, its programme is on, with its own breaks. Outside every window, the shared schedule is on: a programme cut by a window's start stops there, and one still on at its end is joined partway through (`mediaOffset`), as when changing channel.
- The only other change is **covering**: an `exclusive` programme's other airings, and a shared programme the rules don't allow next to an adjacent set time, get a stand-in that fits their slot. Stand-ins are searched from a point picked from the channel's key and the slot, so they vary from slot to slot while every walk picks the same one.
- A set time names a series or film. Shared by code with a household whose library lacks it, it never airs there; Settings says "Not in your library".

So outside the windows and covered slots, every household with the same code sees the same programme at the same point (tested with random channels in `RandomChannelTests`). A series' episode at each set time comes from counting its airings since the channel's first day from the calendar, so any day is found without replaying the ones before. Tuning still walks at most two days.

A household's set times on one channel are a `SetTimes`, with a **set-times code** (the channel number, time zone and set times, in the same Crockford base32 with a check byte as channel codes, through `CodeWriter`/`CodeReader`) to share them with another Apple TV. They're saved as their codes in `AppPreferences` (§3).

**Custom channels.** Settings › Your channels makes a channel on the Apple TV (`CustomChannel`, edited through `ChannelEditorModel`): a name, a number from 20 to 99, episodes, movies or both, one rule (everything, a genre, a series, years or a tag) picked from the library in memory, half-hour slots and commercials (both on by default). Set times on it are made in Settings › Set times, like any channel's. The strategy, seed (1000 + the number) and filler take the defaults. The editor previews how many programmes match and the next three hours, with no server calls. A **channel code** packs the definition into Crockford base32 with a check byte (a mistyped code is rejected, never misread), to type into another Apple TV: with the same schedule code, both then show the same schedule. Custom channels are saved as their codes in `AppPreferences` (§3), and a saved one whose number a newer bundled line-up takes is left out rather than breaking the line-up.

## 9a. Gap filler (commercials): live

Movie channels round each slot up (`padTo`), which leaves gaps; a 100-minute film in 30-minute slots leaves 20 minutes. The plan is to fill them with pre-recorded vintage commercials.

**Already built:**
- The `GapFiller` protocol and `GapFillerRegistry` (`Scheduling/GapFiller.swift`). This extension point works like `ScheduleStrategy`: one file plus one registry line.
- Two fillers:
  - `none`: used when a channel names no filler; the gaps show the "Up next" card.
  - `shuffle` (every default channel): each pass through the pool plays every clip once, in a new `ShuffledOrder` shuffle seeded by the channel key (mixed with a constant, so it doesn't mirror the shows) and the pass number. The same clip never plays twice in a row. It replaced the `derangement` filler, which reused the shows' `a` and `b` (see §9b).
- A per-channel `"filler": "<id>"` setting in `channels.json`, checked when the file loads.
- **Engine:** clips become extra airings inside the programme's slot (`Airing.isFiller`), laid out back to back. A filler is one endless stream of clips per channel (like a strategy's programmes). Each run starts it at an estimate of how many clips aired before (the share of slot time that's gap, over the run, divided by the average clip), and deals from it break after break, so the order carries on across breaks. A clip that doesn't get halfway waits to open the next break. Deterministic, and nothing is stored. A clip still playing when the next programme starts is cut there (`Airing.end`, and the player's `forwardPlaybackEndTime`). A break's last clip that's running late (it started after a slow load) is stopped at its scheduled end, so the Up next card always gets its time; the picture and sound fade out together. Two rules decide what starts: a gap of a minute or less gets no commercials, and clips play back to back, each starting only if at least half of it will play before the next programme. Time without a clip is a blank screen with the "Up next" card and the banner.
- **Helpers:** `ChannelSchedule.programme(at:)` and `airings(…, includingFillers: false)` give the guide and channel list the programme rather than the ad.
- **Player and UI:** clips play as ordinary airings with seamless hand-off. The banner shows "Commercial break · Back at h:mm with <next programme>" when the break starts, then goes, like a programme's. While clips play and the banner's down, a small corner badge says "Commercial break · Back at h:mm".
- **Breaks and mid-rolls:** every slot is rounded up to the `padTo` boundary, so every programme starts on the half hour. After an episode under an hour, the whole leftover is one break. A film (or an episode of an hour or more, `longEpisode`) with more than 10 minutes left over is split into parts by one mid-roll break (up to 20 minutes left over) or two (more), sharing the leftover evenly with the break after it, each mid-roll at most 10 minutes (`longestMidRoll`, `maxMidRolls`), with at least 15 minutes of film between breaks (`shortestPart`), so a short film gets fewer mid-rolls or none. No break has more than 20 minutes of commercials (`longestCommercialRun`); any more of it is blank, with the "Up next" card. Each part is its own airing of the film (`Airing.mediaOffset`: where in the file it resumes; `programmeStart`: shared by the parts). `programme(at:)` and `programmes(from:to:)` give a film whole, for the guide, channel list and banner. The player loads each part like any programme after a break, seeking to its offset. Mid-rolls are the same with commercials off, only blank (a "Now playing … Back at" card), so the schedule never depends on the setting.
- **Up next, then a fade (`upNextLead`, 15 s):** no commercial plays into the last 15 seconds of a break; they're the "Up next" card. The last commercial fades out (0.5 s) into the card, which fades in (0.5 s); 1.2 s before the programme the card fades to black, holds, and the programme fades in.
- **Break indicator everywhere:** `ChannelSchedule.nowShowing(at:)` returns `Onscreen.programme` or `.inBreak(ended:next:)`. The channel list shows "Up next: …" and "Commercial break · starts h:mm" in a break; the guide draws the break as a darker tail on each block (`GuideCell.breakFraction`), and its detail line says "Programme ended · Commercial break until h:mm". One style for all of it (`BreakStyle`).
- **Tests:** `GapFillerTests`.

**Wired up (2026-09-23):**
- **Where the clips come from:** `channels.json` names a Jellyfin library at the top: `"commercials": { "library": "Commercials" }`. The file can still be a plain list of channels; then there are no commercials.
- **Fetching:** `JellyfinClient.fetchLibrary(named:)` finds the library by name with `/UserViews`, then fetches its items (`Video`, `Movie` and `Episode`; home videos come back as `MediaItem.Kind.video`). If the library doesn't exist, the pool is empty and gaps show the "Up next" card as before.
- **No ads as programmes:** `ChannelLineup.schedules(for:fillerPool:code:)` removes the clips from every programme channel, so an ad never airs as a "movie".
- **All default channels** use `"filler": "shuffle"` and `"padTo": 30`, so every programme starts on the half hour: a 22-minute episode is followed by 8 minutes of commercials, a 44-minute one by 16, and a 100-minute film by 20 minutes shared between a mid-roll halfway and the break after it.
- **Scheduled length:** each item stops at its scheduled duration (`forwardPlaybackEndTime`), so clips and programmes keep to the schedule.
- **Pretend commercials (debug builds):** the `-pretendCommercials` launch argument uses 12 ordinary library items, cut to 30–120 s, as the pool. Tested on the simulator against the real server with `-handoffTest`:
  - the "Commercial break · Back at h:mm" banner showed;
  - the break played;
  - the hand-off to the next programme came on time.
- **Tests:** `CommercialsTests` and `CommercialsLibraryTests`.

**Live with the real library (2026-09-23):** the `Commercials` library holds trailers. Breaks played from it on the simulator against the real server.
- **Whole-break banner:** `ChannelSchedule.commercialBreak(at:)` gives the break's span, so "Back at", the bar and the time left cover the whole break, not the current clip.
- **Loading:** commercials follow the same rule as every other item: queued 30 s before the previous one ends, one item at a time. The exception is the programme after a break: it starts loading, paused, in a second `AVQueuePlayer` behind the one on screen as soon as the break starts, so it's buffered (or a transcode has a head start) by the time the commercials end. On the programme's start time the two players swap which is in front (each has its own video layer), since an `AVPlayerItem` can never move to another player; trying to crashes. So the server works on at most two streams, or three in the last 30 s of a commercial. Time the clips don't fill still gets the next item queued 30 s ahead; the player pauses at the end (`actionAtItemEnd = .pause`), shows a blank screen with the "Up next" card, tells Jellyfin to stop any finished transcode straight away, and starts the next item on time. With commercials off, there are at most two streams, only in the last 30 s of a programme.
- **Lightest load on the server:** commercials never make Jellyfin re-encode video, and ignore the quality setting's speed test. They ask once for the original file with no bitrate cap (the quality setting doesn't apply to them), so a clip is never re-encoded just for its bitrate; played as-is or only remuxed, it costs the server almost nothing. If the video would have to be re-encoded anyway (`PlaybackSource.reencodesVideo`, e.g. an unsupported codec), the clip is skipped: its time is blank, with the banner, and the clip is remembered in memory for the session, so it isn't asked about again. Clips that are MP4 H.264/AAC always play.
- **Stall watchdog:** counts only forward progress, and restarts for each new item, so a stream stuck jittering in place is caught after 30 s.
- **Commercials switch:** Settings › Commercials › "Play commercials" (on by default, saved with the other preferences). Off rebuilds the channels with `playsCommercials: false`: every break is blank airtime with the "Up next" card and banner. The clips are still fetched and kept out of the programmes, so programme times are identical either way and everyone with the same code stays in step (tested over a week of schedule). Changing it re-tunes the current channel.
- **Settings:** with diagnostics on, Settings says what was found, for example "42 commercials from “Commercials”", or that the library is missing, not visible to this user, or not yet scanned.
- **Best clips:** short MP4s (H.264 video, AAC audio) at a modest bitrate (1080p at 5 Mbps or less). Those play as-is, so they start instantly and cost the server nothing. Large trailers (4K, or high bitrate) either need more bandwidth than a remote connection has or must be re-encoded.

## 10. Milestones

A record of what was built and checked, in order. Details like the remote controls have changed since; README describes the app as it is now.

1. ✅ **Core package + tests** (no UI): models, `SeededRandom`, `ChannelSchedule`, 4 strategies, and the shared strategy test suite. Runs with `swift test` on the Mac.
2. ✅ **Jellyfin client:** auth (Quick Connect + password), item queries, `PlaybackInfo`/stream URLs, `SecureStore` and `AppPreferences`. Tested against a mock server, and checked live against Jellyfin 10.11.1 on 2026-09-23: sign-in, a 5,927-item library, all 13 default channels, HLS stream URLs, stopping transcodes, and sign-out. (The Keychain test runs in the app's own tests, since milestone 3.)
3. ✅ **Playback MVP:** the tvOS app (`App/GregularTV.xcodeproj`). Sign-in with Quick Connect or a password (with no http/https typed, it tries https, then http), loading the library (pages fetched in parallel), and one channel (the last watched, or the lowest-numbered). It tunes in live, queues the next programme 30 s ahead, shows a card during padding, and pause jumps back to live. It re-tunes if more than 60 s behind live. Failures retry with backoff (5 s up to 60 s), and startup errors retry every 30 s. The Keychain test runs in the app's own tests.
   - Verified on the simulator against the real server (2026-09-23): sign-in, restoring the saved sign-in, joining live mid-programme, the banner, pause then jump to live, recovering by itself after a server outage, and the seamless hand-off to the next programme. The hand-off was tested with the `-handoffTest` debug flag.
   - Added during testing:
     - **Streaming quality:** Auto, plus fixed caps from Maximum down to 480p, in a settings screen opened by clicking the remote. That screen also has Sign Out.
     - **Stall watchdog:** 30 s with no progress counts as a failure and retries.
     - **Debug-build diagnostics line:** player state, how far behind live, and Jellyfin's transcode reasons.
   - **How Auto works:** it never delays playback to measure. A programme loads at the last measured rate, or 8 Mbps before the first measurement. The speed test (`/Playback/BitrateTest`, with a warm-up request first) runs in the background about 20 s after playback starts, and every 10 minutes after that, for later programmes. After a playback failure, Auto measures *before* retrying. The cap is 70% of the measurement. With a fixed quality, no speed test runs, and switching away from Auto cancels one that's pending. App tests check all of this by recording requests. A lower cap forces transcoding, so on a CPU-limited server, lower quality settings can make things worse.
4. ✅ **Channel surfing + banner:**
   - Up/down on the remote change channel, skipping gaps and wrapping round. Rapid presses only preview in the banner, and the app tunes once presses stop for 0.7 s.
   - Left opens the channel list (the channel selector, showing what's on now on every channel). Menu closes it.
   - Channel numbers can be typed on a keyboard: two digits tune straight away, and one digit tunes after 1.5 s. A missing number shows "No channel N".
   - The banner shows on every channel change, and the gap card shows "Up next" with the start time.
   - `ChannelNavigator` (core) and `ChannelSurfer` (app) are unit-tested.
   - Checked on the simulator: number entry, unknown channels, the gap card, and restoring the last channel. Arrow-key input (up/down and the list) is covered by tests only, because the simulator tool can't send arrows.
5. ✅ **Guide grid:**
   - Click (Select) opens the guide, which runs from the current half hour to at least 6 hours ahead, scrolling sideways with focus. Channels run down the side, each programme is a block sized by its time slot, and a yellow line marks the current time.
   - The focused programme's details (title, episode, times) show at the top. Select tunes to that channel, and Menu closes the guide.
   - A Settings button in the header replaces Select-for-settings.
   - The window maths (`GuideWindow`, `GuideCell`) is in the core and unit-tested. Commercial breaks and padding fold into their programme's cell, so the guide never lists ads.
   - Checked on the simulator against the real server. Moving around the grid uses the tvOS focus engine and wasn't checked here, because the simulator tool can't send arrow keys.
6. ✅ **Privacy hardening:**
   - `scripts/privacy-check.sh` runs as the app's first build phase (with script sandboxing off for the app target, because it reads the source tree) and as a `swift test` test. It fails on persistence and logging APIs outside `SecureStore.swift`, `AppPreferences.swift` and `HTTPTransport.swift`. It was checked by adding a violating file: the build failed and named the line.
   - Tests cover: no playback-reporting endpoints, the ephemeral session settings, sign-out wiping credentials, and preferences holding only client settings. The Keychain round-trip test runs in the app's own tests.
   - When the app is launched to host tests, it stays signed out and doesn't play.
   - The README has a privacy statement.
7. ✅ **Polish:**
   - A layered app icon (a "Gregular" wordmark over a slim colour-bar pill and a deep indigo gradient, three layers in parallax) and static Top Shelf images, generated by `scripts/make-artwork.swift`. No server artwork is used.
   - Error states:
     - Server unreachable: retries every 30 s.
     - Playback failure: backoff and retry.
     - Stalls: 30 s watchdog.
     - Channel with no content: hidden.
     - No channels at all: an explanation.
     - Sign-in revoked mid-session: back to sign-in with a reason, instead of retrying forever.
   - Release build checked. Playback diagnostics are a Settings switch ("Show playback diagnostics", off by default), not a build type, and are written in plain language. They never show the server address, token, user or stream URLs.
   - Every on-screen error goes through `FriendlyError`, which gives plain messages, because the system's own error text can name the server's host. App tests check this.
   - Branded launch and loading screens. Version 1.0.

## 11. Testing strategy

- **Determinism:** same seed + items + time → identical `nowPlaying` across runs, and when the input item order is shuffled first. We sort the input by a stable key before calling the strategy, so Jellyfin's API ordering can't change the schedule.
- **Engine:** run boundaries, times before the epoch, a single-item channel, padding and run-end gaps, and sequences carrying on across runs. A laziness test checks that tuning into a 20,000-episode channel pulls at most two days of programmes (the run, and the one before for what aired last). All the maths is in UTC.
- **Strategies:** the shared conformance suite (§5), plus one behavioural test per strategy.
- **Rules:** each rule on its own, set times for a year across clock changes, and `RandomChannelTests`: random small channels on every strategy, with and without set times, checking that nothing airs twice in a row, slots meet with no gaps, every walk agrees, set times are kept, and at every other time the channel is the shared schedule.
- **Privacy:** a test that runs a full session against a mock server, then checks that the app container has no new files and `UserDefaults` is empty.

## 12. Decisions and prerequisites

**Decided (2026-09-23)**
- **Pause:** allowed. Resuming jumps back to live (§7).
- **Last channel:** saved as a single channel number in `AppPreferences` (§3, §8).
- **Jellyfin dashboard:** the app stays invisible. There's no playback reporting of any kind, and no toggle (§3).
- **Channel editing:** hand-edit `channels.json`, which ships with a generic default line-up (§9).

**Decided (2026-09-28)**
- **Shuffle:** every shuffle is a `ShuffledOrder` (Fisher–Yates up to 10 items, a 12-round Feistel network above), new each pass (§9b).
- **Special rules** live in one registry, `ScheduleRules` (§9c).
- **Custom channels** are made in Settings and saved as channel codes: privacy option (a), allowing exactly this in `AppPreferences` (§3, §9c).
- **Programmes at set times** are built, in `channels.json` and in Settings for any channel (§9c).
- **Set times are an overlay** on the shared schedule, so households sharing a code stay in step outside their set times; a household's set times are shared by set-times code (§9c).

**Prerequisites**
- ✅ Xcode 27 with the licence accepted, the tvOS 27 SDK, and the tvOS 27 simulator runtime (verified 2026-09-23). `GregularCore` and `GregularJellyfin` tests pass on macOS and on the Apple TV 4K simulator.
- A reachable Jellyfin server (10.9 or later) for milestone 2 onward. A throwaway Docker instance with a few sample files works well for development.
