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
- `epoch` is a fixed reference date: 2024-01-01 at the day boundary (`DayBoundary.standard`, midnight Pacific). Time since the epoch picks the run, then the programme within it.
- A **strategy is an endless generator** (like a Python generator): the engine pulls at most a day of programmes to reach any moment. It never asks for the whole list. So channels can hold any number of items, and there can be any number of channels.
- Each run depends only on the seed and its number, so any moment can be looked up directly, without replaying the schedule from the epoch.

This design is what makes the privacy requirement cheap to meet. No schedule or library data is persisted, because none needs to be. Two Apple TVs with the same channel config show the same thing at the same moment.

## 3. Privacy rules (enforced in code, not by convention)

| Data | Where it lives | Why it's allowed |
|---|---|---|
| Server URL, for each server signed in to | Keychain (one item: the list of sign-ins, the one watched last first) | Needed to reach the server, and to list it on the main page. Its name is asked of the server when the page shows, and never stored (decided 2026-10-01) |
| Access token + user ID, for each server | Keychain, in the same list | Needed to authenticate, and for Jellyfin's per-user item and playback queries. Signing out of one server revokes and forgets only its sign-in |
| Device ID (random UUID, one per sign-in, made by the app) | Keychain, in the same list | Jellyfin requires a stable device ID in the auth header, and a token goes with the one it was made with. One per sign-in (decided 2026-10-02), so two servers can't link the same Apple TV; sign-ins saved before then keep the ID they all shared |
| Channel definitions (rules, seed, name) | App config (bundled JSON / Swift) | Client-side config, no library content |
| Client settings: last channel **number**, streaming quality, schedule code, diagnostics and commercials switches | `UserDefaults`, through `AppPreferences` only | Client-side preferences; they hold no server data |
| Custom channels, as their channel codes (name, number, rule) | `UserDefaults`, through `AppPreferences` only | Client configuration the viewer typed or picked (decided 2026-09-28, option (a) of the old TODO): a rule's conditions may name genres, series, tags and studios, and nothing else from the library is kept |
| The editing-page switch (off by default) | `UserDefaults`, through `AppPreferences` only | A client setting. The page itself keeps nothing: it edits the custom channels and set times above |
| Set times, as their set-times codes (channel number, time zone, series or film names, times, days) | `UserDefaults`, through `AppPreferences` only | The same option (a): only the names the viewer picked |
| Feeds followed (`SavedFeed`: the link, the first of its ten channel numbers, the version accepted as its file came, when it was last reached, and whether it's expired) | `UserDefaults`, through `AppPreferences` only | Configuration the viewer chose to follow, from someone else, never from the media server (decided 2026-10-26). An update found waits in **RAM only** until *Get Update* |
| Library metadata (titles, IDs, durations, artwork) | **RAM only**, gone on app exit | Needed to build the schedule and guide |
| A programme's tracks, as Jellyfin's `PlaybackInfo` answer describes them (codec, profile, channels, and a sound track's language and name) | **RAM only**, while the request is answered and the stream plays | Needed to know what a stream carries, and to choose a sound track the device plays as it is (decided 2026-10-26) |
| Formats a player turned out not to decode (`UnplayableFormats`: codec and profile names only, read from the stream Jellyfin described) | **RAM only**, gone on app exit | Needed so a format that won't play isn't sent again; the only effect on the server is a shorter device profile (decided 2026-10-25: session only) |
| Password | **Never stored** | Only sent once to get a token (or use Quick Connect instead) |

Enforcement:
- **One network gateway (`JellyfinClient`)** built on `URLSessionConfiguration.ephemeral` with `urlCache = nil`, so nothing is cached to disk. The app loads no images from the server at all; its artwork is drawn by the app. Video is the exception: AVFoundation (or VLC, below) fetches it from the stream URLs, which always point back at the server and carry the token as `ApiKey` (as with every Jellyfin client), so they can appear in the server's and a reverse proxy's logs.
- **No `UserDefaults`, Core Data, SwiftData, or file writes** outside a few allowlisted files: `KeychainStore.swift` (Keychain), `HTTPTransport.swift` (the ephemeral session) and `AppPreferences.swift` (the client settings and custom channels above). A build-phase script fails the build if these APIs appear anywhere else.
- **No third-party SDKs** for analytics or crash reporting. The one external dependency is VLC (libVLC through SwiftVLC, pinned to 1.0.0), Apple TV's fallback player for files AVFoundation can't play as they are (§7). It fetches only the stream URL it's given, with its own network stack, and shows no subtitles; its own log messages are off (`--quiet`).
- **Apple privacy manifest** (`App/GregularTV/PrivacyInfo.xcprivacy`): no tracking, no collected data types, and `UserDefaults` with reason CA92.1 (the app's own settings). The Info.plist sets `ITSAppUsesNonExemptEncryption = NO` (standard HTTPS only).
- **No playback reporting.** The app never calls `/Sessions/Playing`, `/Sessions/Playing/Progress`, `/Sessions/Playing/Stopped` or `/UserPlayedItems`. There's no toggle, so the code path doesn't exist. As a result, nothing shows as "Now Playing", and watched status and resume points on the server stay untouched.
  - **The one exception, `/Sessions/Playing/Ping`:** the transcode keep-alive (§7). It sends only the play session ID the server made for a stream, no item and no position, and Jellyfin only uses it to keep that transcode going (`TranscodeManager.PingTranscodingJob`). `JellyfinPrivacyTests` allows that path alone.
  - **Limits of "invisible":** Jellyfin always records a login in its activity log, and shows an authenticated device under *Devices*. Those are server-side, and no client can avoid them. Every stream request also names its item, since the server has to know what to send, and Jellyfin's log notes its playback decisions; it just isn't watch history. While a transcode is running, the server also does the work, but without playback reports the dashboard can't link it to a "Now Playing" card.
  - No remote control: Jellyfin sends it over a WebSocket, which the app never opens, and the app registers no capabilities (until 2026-10-02 it sent `/Sessions/Capabilities`, which only added a record on the server). `JellyfinPrivacyTests` forbids that call too.
  - **Anonymous where it can be:** `/System/Info/Public` (checking an address before sign-in, and the main page's server names) is asked with no `Authorization` header, so a server that's only probed learns nothing about the device.
- **Logout** revokes the token on the server, deletes that sign-in and drops the in-memory library. If the server can't be reached, the main page says the sign-in still works there and how to cancel it.
- **A new install forgets every sign-in** (`CredentialStore.deleteAll`, on the first launch, when there are no preferences yet): the Keychain can keep an app's items after it's deleted.

Security (untrusted input, checked 2026-09-29):
- **Plain http only on the local network** (`ServerAddress.isAllowed`): localhost, `.local`/`.home.arpa` names (not one-word names, which a network's DNS search domain could send elsewhere), and loopback, private and link-local addresses, in the plain dotted form only: a lone number (`134744072`), hex (`0x08080808`) or zero-padded parts (`010`, octal on Linux and Android) resolve as addresses too, possibly public ones, so they're never local. Carrier-grade NAT (100.64/10) isn't local either: Tailscale uses it, but so do internet providers. `.local` names are trusted as Apple's ATS trusts them, though a hostile device on the network could answer for them. `JellyfinAPI` refuses anything else before sending, on every platform; on Apple TV, App Transport Security is a second line of defence.
- **Transport rules** (`TransportRules`, which every `HTTPTransport` must follow and `TransportConformanceTests` checks): redirects are followed only on the same server (the same scheme, host and port, or `http` up to `https` on the same host), replies are stopped past `largestResponse` (16 MB) as they arrive, and nothing is stored. URLSession drops `Authorization` on a cross-host redirect by itself, but it sends the body again, so a sign-in's password would follow a 307 to another host. `JellyfinAPI` checks the redirect and size rules again on every reply, whatever the transport.
- **Server replies:** the claimed item total is capped (`LibraryQuery.mostItems`), paging stops at an empty page, and each page counts for at most `pageSize` items, so a false total can't plan billions of pages and crash every launch. Server IDs go into URL paths, where they're percent-encoded: they can't change the host or add a query. `TranscodingUrl` keeps only its path and query. The `Authorization` header drops quotes, commas and control characters. Every string Screens hands a front end is plain text; a web front end must escape it.
- **Credentials** are kept by a `CredentialStore` that each platform brings, on the device only and in its secure storage (`KeychainStore` in `GregularKeychain` on Apple's). The shared code has no store of its own, so it can't fall back to an insecure one.
- **Feeds** (decided 2026-10-26; README, *Feeds*): the one request that isn't to the media server, a feed's file, goes through `PublicFile` (GregularJellyfin) on the same `HTTPTransport`: the link must pass `ServerAddress.isAllowed` and carry no user name or password; the request has only `Accept` and, on Apple TV, `User-Agent: GregularTV` (a browser keeps its own, since another would need a CORS preflight); redirects only as `TransportRules` allows; at most `FeedDocument.largestFile` (256 KB), stopped as it arrives, and checked again on the reply. The file (`FeedDocument`) is checked as an `EditingDocument` is, and more: a format version (newer fails closed), at most 10 channels in one block of ten numbers, set times only on its own channels, bounded text, and a picture only as a PNG of at most 32 KB and 256 × 256, its header read before anything decodes it. Its channels keep their last digit in the block the viewer picks, and the viewer's own channels and set times can't use that block (`AppModel.apply`). Updates wait for *Get Update*. Both pages' CSPs allow `img-src data:` for the picture, which comes inside the file.
- **Codes** (channel and set-times) are unauthenticated: the CRC-8 only catches typos. `FixedTimesAreValid` checks set times from a code like any others: times within a day, real dates, and at most `FixedProgramme.mostPerChannel` (24) set times listing `mostTimesPerChannel` (48) times in all per channel, which keeps placing them to a few milliseconds.
- **The editing page** (`EditingPage`, served by the app's `EditingServer`, decided 2026-10-01): off by default; when on, it runs only while its screen is open. Connections are refused unless they come from a private, link-local or loopback address (`EditingPage.isLocal`; Network's `acceptLocalOnly` refused every connection in the tvOS simulator, even from the same Mac, so the app checks the peer itself). Requests must name one of the Apple TV's own addresses in `Host` (against DNS rebinding) and any `Origin` must match it (against cross-site requests), and every data request needs the six-digit code, compared in constant time; five wrong codes from one address refuse it, and 20 in all lock the page. At most 8 connections at once (`EditingServer.mostConnections`); one request per connection, at most 8 KB of headers and 512 KB of body, within 10 seconds. What it's sent is an `EditingDocument`, resolved and checked exactly as codes are (`ChannelLineup.adding`, `Rule.mostConditions`, `FixedTimesAreValid`). The page is one inline file with a strict Content-Security-Policy (no outside requests, no framing) and puts library names on the page only through `textContent`; a test checks it never uses `innerHTML`.
- **Device type** is trusted nowhere: the app reads no other device's name, and Jellyfin authorises by token, not by name. The device name sent is the kind of device, from the app (`AppModel.deviceName`).
- **Sign-in:** only HTTP 401 means signed out (`JellyfinError.unauthorized`); 403 is `forbidden`, an error that leaves the sign-in saved, since a reverse proxy or a parental limit can send it. An administrator's sign-in is confirmed first (`LoginModel.Step.administrator`), and declining cancels it on the server. Signing in over plain `http` shows `LoginModel.unencryptedNote`. A Quick Connect wait stops when the sign-in screen closes (`LoginModel.stop()`), and `AppModel` takes a sign-in only while that screen is up; the password is forgotten when changing server.
- **Library size:** a listing holds at most `LibraryQuery.mostText` (64 MB) of IDs and names, so pages of huge names can't fill memory.
- **Signing out** of a server asks first. Screens decides what's asked (`Confirmation`: `AppModel.signOutConfirmation(for:)`, on the main page and in Settings); the tvOS app presents it.

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
│  │  ├─ LazyPermutation.swift      # 12-round Feistel shuffle, readable at any position
│  │  ├─ ShuffledOrder.swift        # every shuffle: Fisher–Yates up to 10 items, Feistel above; Passes
│  │  ├─ ScheduleCode.swift         # the shared 10-character code → per-channel keys
│  │  └─ SeededRandom.swift         # SplitMix64: deterministic, portable RNG
│  ├─ Channels/
│  │  ├─ ChannelLineup.swift        # loads channels.json, adds custom channels, builds every schedule
│  │  ├─ CustomChannel.swift        # channels the viewer makes, and the codes they're saved as
│  │  ├─ Crockford.swift            # the typing-friendly alphabet of schedule and channel codes
│  │  ├─ ChannelSource.swift        # protocol + registry: what goes on a channel
│  │  ├─ Sources/BasicSources.swift # all, genre, series, years, tag, studio
│  │  └─ ChannelNavigator.swift     # channel up/down, typed numbers
│  ├─ Guide/GuideWindow.swift       # the guide's time window and cells
│  ├─ Network/LocalNetwork.swift    # which addresses are on the home network (plain http, the local pages)
│  ├─ Playback/StreamingQuality.swift  # quality caps, Auto's bitrate rule, step-down ladder
│  ├─ Playback/SpeedTest.swift   # Auto's speed test: downloads that grow until one is long enough to time
│  ├─ Preferences/AppPreferences.swift # the only UserDefaults: client settings, custom channel codes, feeds followed
│  └─ Resources/channels.json       # the channel line-up
├─ Sources/GregularJellyfin/        # 2. THE JELLYFIN CONNECTION: Foundation, GregularCore (any platform)
│  ├─ HTTPTransport.swift           # the app's own network path (ephemeral, no cache/cookies), TransportRules
│  ├─ JellyfinAPI.swift             # request building, auth header, JellyfinError
│  ├─ JellyfinServer.swift          # pre-login: server check, Quick Connect, password → Credentials
│  ├─ JellyfinClient.swift          # signed in: libraries, playback sources, speed test, stop transcode,
│  │                                # sign out; conforms to MediaLibrary and StreamSource
│  ├─ LibraryQuery.swift            # paged /Items → [MediaItem] (Jellyfin types → MediaItem.Kind)
│  ├─ Playback.swift                # DeviceProfile, PlaybackSource (→ MediaStream)
│  ├─ CredentialStore.swift         # Credentials, the CredentialStore every platform brings, in-memory store
│  ├─ PublicFile.swift              # the one request not to the media server: a published file (a feed)
│  └─ ServerAddress.swift, ClientIdentity.swift, JellyfinJSON.swift   # ServerAddress: plain http only on the LAN
├─ Sources/GregularKeychain/        # APPLE ONLY: KeychainStore, the CredentialStore on Apple platforms
├─ Sources/GregularScreens/         # 3. WHAT THE SCREENS DO, not how they're drawn: Foundation, Observation,
│  │                                #    GregularCore (and GregularJellyfin, for sign-in only)
│  ├─ App/                          # AppModel (signed out / loading / watching), LoginModel, FriendlyError,
│  │                                # ErrorKind (each error's kind, for retries and words), DebugOptions,
│  │                                # DemoCredentials
│  ├─ Player/
│  │  ├─ PlayerDeck.swift           # the ONLY way to actual video: a queue player with its own picture
│  │  ├─ ChannelPlayer.swift        # every playback decision: tuning, hand-offs, breaks, retries, head
│  │  │                             # starts, quality; plays on two PlayerDecks
│  │  ├─ ProgrammeSettings.swift    # one programme's fix, choice of player and Auto cap, and the cap rules
│  │  ├─ UnplayableFormats.swift    # what the device's players turned out not to decode, this session
│  │  └─ ChannelSurfer.swift        # channel up/down with preview, typed numbers, the list
│  ├─ Channels/LibraryChoices.swift # the library's names to pick from, and preview lines
│  ├─ Editing/                      # the editing page: EditingPage (requests), EditingDocument (the JSON),
│  │                                # HTTPMessage, EditingPageHTML (the page itself)
│  ├─ Feeds/                        # FeedDocument (a feed's file: read, checked, placed, made), Feed (one
│  │                                # followed, its status and what's new); following and checking: AppModel+Feeds
│  ├─ Watch/WatchModel.swift        # the watch screen's rules: banner, overlays, curtain, remote actions,
│  │                                # and the words on the banner, cards and badge
│  ├─ Remote/RemoteControls.swift   # the button tables (one per screen) and hints
│  └─ Text/                         # displayTitle / displaySubtitle, quality labels, break wording, Settings' words, the player's (PlayerText: diagnostics, the stream line, why a programme stopped; decks report a DeckActivity, not words)
├─ Tests/GregularCoreTests/         # schedule, strategies, commercials, guide, privacy, layers
├─ Tests/GregularJellyfinTests/     # Jellyfin client and sign-in (against a mock server), privacy
├─ Tests/GregularScreensTests/      # player and watch screen on fake decks: no video, no Apple TV
├─ scripts/                         # privacy-check.sh (runs in the build), layer-check.sh, make-artwork.swift
└─ App/ (Xcode tvOS target "GregularTV", shown as Gregular TV)   # 4. APPLE TV: SwiftUI, AVFoundation, UIKit
   ├─ GregularTVApp.swift, RootView.swift, DemoMode.swift   # launch; AppModel with AVFoundation decks
   ├─ Login/          LoginView (draws LoginModel)
   ├─ Player/         WatchView (draws WatchModel), TVDeck (PlayerDeck on AVQueuePlayer, and VLC per item),
   │                  VLCItem, DeckSurface, VideoSurface, FrameRateMatching, ChannelListView, SettingsView, SettingsRows, BreakStyle
   ├─ Editing/        EditingPageView (address and code); Shared/LocalPageServer serves LocalPage on the home network
   ├─ Remote/         RemoteControls+SwiftUI (attaches the tables), RemoteGestures (clicks, slides, touches)
   ├─ Guide/          GuideView (scrolling EPG grid)
   └─ GregularTVTests/  app-hosted tests (Keychain, player on AVFoundation, commercials, surfing, remote)
```

**Dependencies.** `GregularJellyfin → GregularCore`; `GregularScreens → both`; the Apple TV app → `GregularScreens` and `GregularCore`, never Jellyfin. The logic knows nothing about Jellyfin, networking, AVFoundation or UI: it defines what it needs from a server (`MediaLibrary` for programmes and commercials, `StreamSource` for playable streams and the speed test) and works with any implementation. `GregularScreens` knows what the screens do but not how they're drawn or how video plays: `ChannelPlayer` reaches video only through `PlayerDeck`, and only `AppModel`, `LoginModel` and `DemoCredentials` know the server is Jellyfin. Text on screen names it through `AppModel.serverName` (and the sign-in screen's server-specific words come from `LoginModel`), and the server's own reasons for converting a stream reach the player in plain words, so nothing else depends on Jellyfin's wording. The Apple TV app only draws the models, provides `TVDeck` (which reports only what it alone knows, such as why it's buffering; `ChannelPlayer` writes the diagnostics line), and connects the Siri Remote. `scripts/layer-check.sh` enforces all of this, and runs as a test. Inside the logic, `Scheduling` knows nothing about where items come from; strategies only see `[MediaItem]` and an RNG.

**The web version** (`Web/`, built 2026-10; WEB_PLAN.md) keeps the first three parts as they are (the same channels, schedules, banner rules, remote tables and words) and brings its own: `GregularBrowser` (requests through `fetch()`, the sign-ins encrypted in the browser, preferences in local storage) and `GregularWeb` (pages that draw `AppModel`, `LoginModel` and `WatchModel`, a `PlayerDeck` on `<video>` elements, and the keyboard connected to `RemoteControls`). The Swift is compiled to WebAssembly and runs in the browser; gregular.tv only serves the files.

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

**A possible later step (decided 2026-10-26: not now).** TV before streaming was organised by audience and time of day: a network's day ran morning news, daytime soaps and game shows, after-school kids' shows, early-evening reruns, prime-time first runs and movie nights, then late-night talk and a late movie; an independent station ran cartoons, reruns and movies; a kids' channel became a classic-sitcom channel at night. The era line-up (§9) gets as close as one all-day shuffle per channel can. The next step would make each default channel a network whose day is time blocks, each with its own source, and could add a "TV year" setting that sets every channel's eras around one year. Both need this hook built.

## 6. Schedule engine math

- **Runs:**
  - Time from the epoch is cut into runs of a day, from one day boundary to the next (`DayBoundary.standard`: midnight Pacific; the one place to change it, to 2 am say), following daylight saving: 23, 24 or 25 hours. A channel with a programme longer than the shortest day gets runs of whole days, enough for it. Run starts come from the calendar (`runStart(_:)`), not a fixed length.
  - Each run pulls programmes from its own stream and plays them **back to back**; a programme never waits for a boundary. (Until 2026-09-23 runs were split into 2-hour-plus blocks that programmes couldn't cross, which left movie channels with up to two hours of dead air after a film.)
  - Near the end of a run, strategies with `mayReorderToFit` may pass over up to 15 programmes that wouldn't finish in time, to find one that does.
- **Leftover time:** each run is planned whole, then moved later by the time it can't fill, so its programmes play right up to the day boundary and the leftover (once a day) comes first: a break just after the boundary, joined to the last slot of the run before, like padding. It's filled with commercials up to the next programme, at most 20 minutes of them (`longestCommercialRun`); any more is blank, with the "Up next" card.
- **Continuity:** run `r` starts the strategy at position `⌊r × runLength / averageSlot⌋`, an estimate of how many programmes aired before. A sequence may repeat or skip an item where runs meet, once a day. That's the price of never building or replaying the full schedule.
- **Lookups:**
  - `tune(at:)`, `programme(at:)` and `commercialBreak(at:)` walk from the start of the run: at most a day of programmes, whatever the library size (tested with a 20,000-episode channel).
  - `airings(from:to:)` walks forward slot by slot, across runs.
- **Padding:** optionally rounds each slot up to the next 5/15/30-minute boundary.
- **Runtime:** items with no or zero runtime are filtered out when loading.

## 7. Jellyfin integration

- **Auth:** Quick Connect is the main method, because typing on a TV is painful. The fallback is `POST /Users/AuthenticateByName`. Every request sends the header `Authorization: MediaBrowser Client="Gregular TV", Device="Apple TV", DeviceId="<uuid>", Version="x", Token="<token>"`, with the device ID of that sign-in, except `/System/Info/Public`, which is asked anonymously.
- **Items:** `GET /Items?Recursive=true&IncludeItemTypes=Episode,Movie&Fields=…` with only the fields we need: the defaults (`RunTimeTicks`, `SeriesId`, `SeriesName`, `ParentIndexNumber`, `IndexNumber`, `Name`, `ProductionYear`, `PremiereDate`) and, asked for, `Genres`, `Tags` and `Studios` (names only are kept), with images and user data off. Series are fetched the same way, for the genres, tags, studios and year their episodes inherit. Results are paged.
- **Playback:** `POST /Items/{id}/PlaybackInfo` with a tvOS `DeviceProfile` (direct-play HEVC/H.264 + AAC/AC3/EAC3 in MP4/MOV/HLS, and transcode everything else to HLS). Then:
  - Direct play: `/Videos/{id}/stream.{container}?Static=true…`.
  - Otherwise: Jellyfin's `TranscodingUrl` (HLS: a remux or a transcode).
  - Either way, the player seeks to the live offset itself. Jellyfin's HLS transcoder restarts at the segment requested.
  - Stream URLs carry the token as `ApiKey`, the same as every Jellyfin client, because AVPlayer can't reliably send headers on segment requests.
  - **Subtitles are off in v1.** Otherwise Jellyfin burns in each file's default subtitle track, which forces a full video transcode that a Raspberry Pi can't sustain. The request sends `SubtitleStreamIndex=-1` *and* `MediaSourceId` (the item's ID): Jellyfin only honours a stream index for a request that names its media source (`MediaInfoHelper.SetDeviceSpecificData`), so for a while it ignored the -1, picked the default track, and burned in any format the profile didn't list. Every subtitle format is also declared `External` in the `DeviceProfile`, as a second line of defence. A subtitle track inside a file the Apple TV plays as-is follows the Apple TV's own Subtitles setting. Later, subtitles can come as WebVTT inside HLS (`SubtitleProfile` method `Hls`), which doesn't need a video transcode.
  - **A re-encode makes H.264.** The transcoding profile lists `h264,hevc`: either is copied as it is, and when the video has to be re-encoded, Jellyfin makes the first, far less work than HEVC (which a Raspberry Pi can't make in real time).
  - When leaving an item, `DELETE /Videos/ActiveEncodings` stops the transcode right away. This is resource cleanup, not playback reporting.
  - **Apple TV's fallback player, VLC.** A file AVFoundation can't play as it is (an MKV, DTS sound, 10-bit H.264, HEVC tagged `hev1`) would otherwise be converted by the server: at least repackaged as HLS, which on a small server means ffmpeg starting at each tune-in and staying ahead of playback. Swiftfin avoids that by playing almost everything in VLC, so the server only sends the file. Gregular asks Jellyfin about AVFoundation first (`PlayableFormats.appleTV`, with `CodecProfiles` for what AVFoundation is fussy about); if it can't play the file as it is, it asks about VLC (`PlayableFormats.vlcOnAppleTV`: the common containers and codecs, no rarer ones, whose readers are less tested), and if VLC can, VLC plays the file as it is (`MediaStream.Player.addOn`). Otherwise (over the quality cap, say) the server converts it for AVFoundation as before. `TVDeck` plays each item on its player; a VLC item has a VLC player of its own, so it buffers, paused, while the item before it plays, like a queued AVFoundation item, and hand-offs work in every direction. VLC holds 3 s of stream (`--network-caching=3000`, three times libVLC's default), filled while it waits paused, to ride out a moment's slow server or Wi-Fi; AVFoundation waits until it can play on rather than starting into a stall (`automaticallyWaitsToMinimizeStalling`, its default, set on purpose). `VLCSetupTests` checks both.
  - **Keep-alive.** Jellyfin stops an HLS transcode, and deletes its segments, a minute after the player last asked for one. A player that has buffered enough, or holds the programme after a break paused on the standby deck, stops asking, so the transcode was killed and restarted mid-programme, a stall. Every 20 s the player now tells Jellyfin it still wants each converted stream it holds (`/Sessions/Playing/Ping`, §3). Not while paused, which can last hours: resuming jumps to live anyway.
- **Seamless next programme:** 30 seconds before an item ends, prepare the next item in an `AVQueuePlayer` (or VLC), so the hand-off doesn't show a loading spinner. A programme straight after this one that the server converts is asked for 90 s before (`ChannelPlayer.convertedNextLead`, 2026-10-26) and starts buffering, paused, on the standby deck, swapping in on its start time as the programme after a break does (`preloadConvertedNext`), so the server gets well ahead of it rather than starting 30 s before. One the server sends as it is is held (`earlyNext`) and queued at the usual 30 s, as buffering it sooner would only take this one's bandwidth. Not while the server converts the programme on now, so a small server never makes two conversions for longer than before.
- **Match frame rate** (Settings › Picture, Apple TV, off by default): asks Apple TV to switch the TV to what's on screen's frame rate and dynamic range (`AVDisplayManager.preferredDisplayCriteria`), so a 24 fps film isn't shown at 60 Hz with judder. A bare `AVPlayerLayer` never asks by itself. Apple TV only switches with Match Content on in its own settings, which Settings says when it's off; the screen goes dark for a moment at each switch, such as into and out of commercials.
- **Pause and jump to live:** Play/Pause really pauses, and the banner shows `PAUSED · live is +mm:ss ahead` while it's paused. Pressing Play again **jumps back to live**: it recomputes `nowPlaying` for the current time and tunes to it, even if a different programme is on by then. There's no DVR-style resume from the paused point. That keeps the channel honest, and we don't need to store anything.
- **The stream only restarts on an explicit change:**
  - **What restarts it:** a different channel, a different quality, a new schedule code, or resuming from pause (which jumps to live). Also recovery: a failed load, a 30-second stall, or falling more than 60 s behind live.
  - **Head start for re-encoding:** tuning into a programme Jellyfin has to re-encode (`MediaStream.Delivery.reencoded`, from Jellyfin's `TranscodeReasons`: any reason that isn't the container's or the sound's; diagnostics also tell apart a stream only repackaged and one with only its sound converted), the player seeks 20 s past live, buffers paused with a blank screen ("Getting this ready · starts in N s"), and plays when live reaches that point. Each failure on the channel doubles it, up to 2 minutes; changing channel resets it, and the retry wait. The heaviest re-encodes start at twice that (`ChannelPlayer.heavyHeadStartFactor`, 2026-10-26): tone mapping HDR to SDR, 10-bit to 8-bit, and deinterlacing (Jellyfin's `VideoRangeTypeNotSupported`, `VideoBitDepthNotSupported` and `InterlacedVideoNotSupported`; `MediaStream.isHeavyReencode`, decided in the Jellyfin layer). Trouble with one takes the same ladder as any re-encode, whose first step is already 720p. It helps when the transcode is slow to start or roughly real-time; a server that converts well below real time will still stall eventually. Checked live on 2026-09-23: a *Guardian* episode that stalled every time played after a 20 s head start.
  - **Re-encoding that can't keep up:** when a re-encoded programme fails, stalls or falls over a minute behind live, the retry asks for 720p, then one step lower on each further failure (4 → 1.5 Mbps), for that programme only, through the programme fix (so Settings shows it). The server's processor is the bottleneck, so Auto doesn't re-measure the connection first. A stream that fails during a head start is retried at once, not after the head start.
  - **Too little left:** a programme Jellyfin would re-encode isn't started with under 3 minutes (`minReencodedTimeLeft`) to go; the screen is blank with "Up next" until the break after it, or the next programme.
  - **"Trouble with this programme?"** (Settings, while a programme is on): *Step Down Quality* restarts it one step lower on the fixed ladder (20 → 10 → 4 → 1.5 Mbps) and steps down again after 4 s of buffering; *Play at 720p* restarts it at 4 Mbps; *Standard* goes back. In memory only, for that programme: changing channel, changing quality, or the next programme starting clears it. The programme loaded behind a break, and commercials, always use the standard rules.
  - **Sound conversion that can't keep up, and Stereo Sound:** a stream whose only conversion is its sound (`MediaStream.Delivery.soundConverted`) that fails, stalls or falls a minute behind live is retried with less sound work (`ProgrammeSettings.askForLessSoundWork`): stereo (`StreamRequest.stereoSound`: Jellyfin's transcoding profile asks for at most 2 channels, `PlayableFormats.withStereoSound`), which is less to make, where there's surround to mix down; then a head start, as a re-encode gets. A browser already gets stereo and has no VLC, so its first step is the head start (decided 2026-10-25: retry first, then measure). Never a lower bitrate, which would make the server re-encode the video too, so Auto doesn't measure for it; after both steps, the trouble may be the connection's. Every converted stream (sound or video) buffers `convertedForwardBuffer` (60 s) ahead, and `convertedBufferingLimit` (10 s) of buffering on one takes its ladder's next step without waiting for the 30 s stall; a re-encode at the lowest quality has no next step. VLC can't help: it's asked before the server converts anything, so a sound conversion means VLC can't play the file as it is either. *Stereo Sound* is also a switch in the same section wherever the device plays more than 2 channels (`ChannelPlayer.offersStereoSound`), kept in `ProgrammeSettings`: cleared by the next programme or a channel change, kept through a quality change.
  - **Choosing a sound track** (2026-10-26): where Jellyfin's answer converts the sound (a sound reason in its `TranscodingUrl`), `JellyfinClient` looks for another of the file's sound tracks a conversion copies as it is (`MediaSource.soundTrackToCopy(into:)`: its codec in `convertedAudioCodecs`, no more channels than `mostAudioChannels`, in the same language as Jellyfin's own choice, `DefaultAudioStreamIndex`, and not a commentary or audio description by its name; the most channels, then the first) and asks once more with `AudioStreamIndex`. That request alone adds `DeviceProfile.CodecProfile.firstSoundTrackOnly` (`IsSecondaryAudio` false, as Jellyfin's web app sends for browsers that can't switch tracks), because a player plays a file's own track: a file whose chosen track isn't its first comes repackaged, carrying that track alone (`SecondaryAudioNotSupported`, a repackaging reason in `PlaybackSource.delivery`). The second answer is taken only if it's a conversion that doesn't convert the sound; otherwise, or if asking fails, the first stands, so it's never worse. A track's language and name are read in memory with its codec, only to choose. Not checked against a real Jellyfin server: the tests use recorded answers.
  - **FLAC and 7.1 on Apple TV** (2026-10-26, A4): `PlayableFormats.appleTV` plays FLAC as it is in a file, and a conversion keeps up to 8 channels (it was 6), so 7.1 E-AC-3 is copied rather than mixed down, and 7.1 sound is made as 7.1. Both play in Apple's player in the simulator (`AppleTVSoundTests` makes each with AVFoundation's encoder and plays it), not yet checked on an Apple TV. As a backstop, a "can't decode" on a stream in only the safest formats asks for stereo sound for its retries (`ChannelPlayer.fail`), since the formats themselves can't be ruled out but the channels can be.
  - **Files a player can't decode** (decided 2026-10-25, for any device and format): a deck reports a decode failure as `UnplayableMedia` (AVFoundation's decoder-not-found, decode-failed, format-not-recognised, failed-to-parse and undecodable-data errors; VLC's error state; the browser's `MEDIA_ERR_DECODE` and `MEDIA_ERR_SRC_NOT_SUPPORTED`, and hls.js media errors). A browser gives `MEDIA_ERR_SRC_NOT_SUPPORTED` before anything loads for a video it couldn't fetch at all, too (a missing file and a refused connection alike: checked in Chromium, and it's what the HTML standard says), so `VideoDeck` then fetches the stream's first byte (`reach` in `hls-player.js`): sent, it's the format's; refused, the server's (`PlaybackStopped`); no answer, the connection's. Until 2026-10-26 it took every such error as the format's, so on an iPhone (which plays every stream with Safari's own HLS) any stream that failed to start said it couldn't be played, and elsewhere a format was ruled out for a network blip. A decode failure is `ErrorKind.unplayable`. Each stream says what it carries (`MediaStream.contents`: the file's video and sound from Jellyfin's `MediaStreams`, or a conversion's output, the first codec its `TranscodingUrl` allows). `UnplayableFormats.learn` rules out the first format the failed stream carried that isn't one of the safest (`PlayableFormats.safestFormats`, the first conversion codecs: H.264 and AAC), the sound first; the next request leaves it out (`StreamRequest.unplayable`, `PlayableFormats.without`: a video profile off its codec's limit, else the whole codec, from what's played as it is and what a conversion copies), at once, with no backoff. Each failure shrinks a finite list, so it ends: a stream in only the safest formats that won't play is retried as any failure (`ChannelPlayer.safestFormatRetries`, 2, with the usual backoff), then `ChannelPlayer.Status.cantPlay` until its slot ends ("This programme can't be played on this device", with Up next), and the programme isn't asked for again. Learned for the session (the channel player's life), in memory only.
  - **Play in VLC** (Apple TV, in the same section): a switch that shows whether VLC is playing the programme on now (`ChannelPlayer.programmeIsOnAddOn`). Turned on, it restarts the programme asking Jellyfin about VLC first (`StreamSource.stream(…players:)`, `ChannelPlayer.setPrefersAddOn`), so VLC plays it if it can play the file as it is, even where AVFoundation could too; if VLC can't, AVFoundation keeps it as usual and the switch stays off, saying why. Off only undoes the asking: a file only VLC plays stays in VLC. In memory only, for every part of that programme (the part behind a break too), not its commercials (each clip in VLC would need a player of its own): changing channel or the next programme starting clears it; changing quality doesn't.
  - **What never does:** opening or closing the guide, channel list, Settings or banner; choosing the channel or quality that's already selected; toggling diagnostics; or the app briefly becoming inactive (Control Center, a notification). `start()` does nothing when already playing, and only a real trip to the background stops the player.
  - **Tests:** `StreamStabilityTests` counts re-tunes to check this.
- **Drift correction:** coming back to the foreground or switching channels uses the same "tune to live" path, so it's one code path for every case.

## 7a. Stream quality: where each decision lives

Every place the app decides, asks for, or reacts to a stream's quality, by type (the decisions themselves, with their dates, are in §12). How one programme gets played:

1. **What can play:** `PlayableFormats`, one per player: `.appleTV`, `.vlcOnAppleTV`, and `.browser(alsoPlays:)`, from what the browser confirms through `MediaSource.isTypeSupported` (`WebApp`). Each request turns it into Jellyfin's `DeviceProfile` (`Playback.swift`), less what a player turned out not to decode (`PlayableFormats.without`, from `UnplayableFormats`), and with sound mixed down if asked (`withStereoSound`).
2. **The cap:** `ProgrammeSettings.cap(at:)`. A fix for the programme, else the fixed quality, else Auto's cap after connection trouble, else none. A commercial plays at its break's (`ProgrammeSettings.forBreak`): its programme's cap and stereo sound, then less if a clip's conversion can't keep up, for that break only.
3. **The request:** `JellyfinClient.playbackSource`. It asks `PlaybackInfo` for each player in `MediaStream.Player.order`. For a conversion, it may ask once more with a sound track the conversion copies (`withASoundTrackToCopy`). `PlaybackSource.delivery` reads Jellyfin's `TranscodeReasons` into the four kinds (`MediaStream.Delivery`), and marks the heaviest re-encodes (`isHeavyReencode`).
4. **Playing it:**
   - The decks: `TVDeck`, with a `VLCItem` per item for VLC, and `VideoDeck`, with hls.js or the browser's own HLS.
   - A conversion buffers further ahead (`convertedForwardBuffer`).
   - A re-encode starts past live (`Timings.transcodeHeadStart`, twice that for the heaviest).
   - The next programme is asked for ahead of time (`prepareNextLead`; `convertedNextLead` for one the server converts).
5. **Trouble:** `ChannelPlayer.fail`, by `ErrorKind`:
   - signed out: sign in again;
   - can't decode: rule out a format (`UnplayableFormats`), or, for the safest formats, retry (`safestFormatRetries`) and then say it can't play;
   - a conversion that can't keep up: ask for less (`ProgrammeSettings.askForLessReencoding`, `askForLessSoundWork`);
   - connection trouble in Auto: measure (`SpeedTest`) and cap that programme.

   Buffering limits: `stallTimeout`, `convertedBufferingLimit`, `stepDownAfterBuffering` and `maxDriftBehindLive`.
6. **The words:** `PlayerText` (diagnostics, the stream line, why a programme stopped), `SettingsText`, `FriendlyError`.

Subtitles are off at every layer (§7).

**Still open (2026-10-26):**
- **Not yet checked on a real Apple TV or a real Jellyfin server,** only in tests and against the demo server:
  - FLAC and 7.1 on Apple's player: declared on 2026-10-26 (A4) after playing in the tvOS simulator (`AppleTVSoundTests`), which uses the Mac's decoders. A real Apple TV should play a FLAC-in-MP4 film and a 7.1 E-AC-3 one as they are, and a 7.1 film's conversion in 7.1. If it can't, FLAC is ruled out after one failure, and a stream in the safest formats is retried with stereo sound, so the cost is one failed start, not a programme that won't play. FLAC isn't copied into a conversion (untested in a stream);
  - TrueHD in VLC;
  - a DTS film's sound conversion;
  - VLC's 3 s network buffer;
  - the second request with a chosen sound track (`IsSecondaryAudio`);
  - the heaviest re-encodes' reasons.
- **A doubled ffmpeg start, suspected** when joining a conversion part-way. It needs the server's log to confirm.
- **VLC reports no buffered seconds,** so the head start and resume rules don't see its buffer. That's harmless while VLC never plays a conversion.
- **Web commercials stuttering, reported but unconfirmed:** reported with any quality but Maximum. The likely cause, the next programme's re-encode buffering during the break, needs a server that converts to check. Since commercials follow their programme's cap (2026-10-26), a clip above it is now re-encoded too: more work for the server during breaks, so check this again with that in mind.

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
- **Variety decides the rest, from the library connected (`ChannelVariety`).** A channel marked `needsVariety` (every default channel but the two catch-alls, 1 and 10) is also hidden when its programmes can't fill a day without repeating too soon: a series at most about once a day, a film at most about once every three days (one pass of the shuffle each way). A mixed channel is hidden, too, when its series can't carry at least half the TV airtime it asks for (`ChannelVariety.leastTVCarried`), so a classic-TV channel in a library with no classic TV doesn't become a film channel. So a small library shows fewer, broader channels, and a large one shows them all.
- A genre rule can list alternatives, such as `["Science Fiction", "Sci-Fi", "Sci-Fi & Fantasy"]`, because metadata providers name genres differently.
- Channel numbers are fixed by config, so hidden channels leave gaps, like real TV. The surfer skips the gaps.

**Default line-up (2026-10-26): eras, laid out like a cable line-up before streaming.**

Mixing programmes from decades apart on one channel felt like a jolt, so every themed channel keeps to an era; Viewers Like You and Workshop have the widest (1960 to now, decided 2026-10-26), since documentaries, British drama and how-to date less. The line-up follows how US TV was organised from the mid 1980s to the early 2000s, when a home had about 20 to 60 channels and watched about 14: channels were brands for an audience, not genre filters. Broadcast networks aired broad prime time (sitcom blocks, dramas, a couple of movie nights a week); independent stations filled their days with reruns and movies; kids' channels and Saturday mornings had cartoons; cable channels had comedy, sci-fi, factual and lifestyle programming; classic-TV channels (Nick at Nite, TV Land) kept old shows in their own home; movie channels split into classics (AMC, TCM) and premium (HBO). Reruns lagged first runs by years, not decades, so each era starts a few years early. Names say what a channel plays, the way cable brands did, without using any real brand.

Built from the existing tools: each channel is an `all-of` its era's `years`, its genres, and `not` the genres that don't belong (kids' channels need Kids, Family or Children; the network, comedy, family and classic-TV channels leave out Kids, Children and Horror; the networks also leave out Documentary), with the film share from the kind of channel it's modelled on. The one rule added for it is `studio` (2026-10-26, the same day): PBS's Masterpiece side, British costume and literary drama, can't be told from other drama by genre, but can by the network or company that made it. Later the same day, public television (Viewers Like You, after PBS, in place of Field Trip) and how-to (Workshop, after Create and Food Network together, in place of Daytime, whose game shows, talk, soaps and reality the networks already air) replaced two channels; Food Network on its own would rarely have had the variety to be shown. Every channel has the same shuffled commercials; Silver Screen and Premiere leave out `padTo`, as a custom channel with half-hour slots off does, so their films follow each other with no breaks but the day boundary's. Numbers kept no themes from the 2026-10-01 line-up except Gregular (1) and Movies (10), so set times saved on 2–9 or 11–19 stay on the number, under a new theme. An episode counts by its own year (its series' year if it has none), so a long-running show's eras air on different channels.

| # | Name | Modelled on | Source rule | Years | Films |
|---|---|---|---|---|---|
| 1 | Gregular | the house channel | everything | any | 35% |
| 2 | Rabbit Ears | Nick at Nite, TV Land | everything but Horror | 1950–1979 | 10% |
| 3 | Primetime Gold | the Big Three networks | everything but Kids/Children/Documentary/Horror | 1978–1996 | 15% |
| 4 | Sweeps Week | networks, mid 90s to 2000s | the same | 1994–2010 | 15% |
| 5 | Next Episode | networks today | the same | 2008– | 15% |
| 6 | Saturday Morning | Saturday-morning cartoons | Animation/Anime, and Family/Kids/Children, but not Horror | 1960–1993 | 20% |
| 7 | After School | 90s kids' cable | Family/Kids/Children, not Horror | 1986–2006 | 30% |
| 8 | Family Room | family TV today | the same | 2005– | 35% |
| 9 | Late Show | independent stations, superstations | everything but Kids/Children/Documentary/Nature/History | 1968–1990 | 50% |
| 10 | Movies | | every film | any | films only |
| 11 | Laugh Track | comedy cable | Comedy/Sitcom/Stand-Up, not Kids/Children/Horror | 1978–1999 | 35% |
| 12 | Punchline | comedy today | the same | 1998– | 35% |
| 13 | Sci-Fi Syndicate | the Sci-Fi Channel, syndicated sci-fi | Science Fiction/Sci-Fi/Sci-Fi & Fantasy/Fantasy | 1966–1999 | 40% |
| 14 | Other Worlds | sci-fi today | the same | 1997– | 40% |
| 15 | Viewers Like You | PBS | Documentary/Nature/History/Science/Music/Arts, or Drama/Comedy/Sitcom/Crime/Mystery/History/War/Romance/Food/Reality from a British network or film company (`studio`: BBC One, ITV, Channel 4, Channel 5, PBS, Masterpiece, BBC Films, Film4, Merchant Ivory, Working Title…), not Kids/Children/Horror | 1960– | 25% |
| 16 | Workshop | Create, Food Network | Food/Home and Garden/Travel | 1960– | TV only |
| 17 | Silver Screen | AMC, TCM | every film | 1930–1966 | films only, no slots |
| 18 | Video Store | premium movies in the VHS era | every film | 1980–1999 | films only |
| 19 | Premiere | premium movie channels | every film | 1998– | films only, no slots |

`ChannelConfigTests` checks each themed channel's years are one unbroken run from 1930 or later, and where a comedy, a cartoon for grown-ups, a kids' show and horror films land.

**The mix (`ShuffledMix`, id `shuffled-mix`).** Under `shuffled-shows` every title gets one turn per pass, so a library with far more films than series fills a mixed channel with films. A mixed channel instead asks for a share of its airtime for films (`"films": 0.35`), and the library can move it: if the series can't fill their part without one coming round more than about once a day, films take the rest, and the other way round (`ChannelVariety.filmShare(wanted:)`). The share of airtime becomes a share of slots (films are longer, so they take fewer slots than their airtime). Positions come in blocks of 10, each with exactly its share of film slots at shuffled places, so films don't arrive on a fixed beat. The series and the films each keep their own Shuffled Shows order (§9b), counted by how many slots of that kind came before: every series once per pass of the series, one episode further each pass, and every film once per pass of the films. It also tells the engine its average slot (films' share at the films' average, the rest at the series'), for where each run's stream starts.

What a medium library gives (`SCHEDULE_AUDIT=1 swift test --filter ScheduleAudit`, 90 series and 450 films made up with typical lengths, genres and years, the series leaning recent): 7 of the 19 channels are on (Gregular, Sweeps Week, Next Episode, and the four film channels: Movies, Silver Screen, Video Store, Premiere), each mixed one near its asked share. A library of 25 series and 120 films shows 4 (Gregular, Next Episode, Movies, Silver Screen). The made-up library spreads its series evenly over 13 genres and over 55 years, so every era of every genre is thin; a real library, bunched in the genres and years its household likes, shows more of the channels for those. (The 2026-10-01 line-up, without eras, showed all 16 and 7 of 16.)

Source types available: `all`, `genre`, `series`, `years`, `tag`, `studio` (all matched case-insensitively by name; an episode's genres, tags and studios are its series'), and `all-of`, `any-of` and `not`, which combine other sources (`{ "type": "not", "source": { "type": "tag", "anyOf": ["Christmas"] } }`) and nest to any depth. A channel's optional `itemTypes` narrows any source to `Episode` or `Movie`. The config format looks like this:

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
- **`ShuffledOrder.Passes`:** a new shuffle for each pass through the items (pass `⌊position / N⌋`), seeded by the key and the pass number, with every pass split the same way: one half of the items (picked once from the key) is shuffled into its first half, the rest into its second. So what closed one pass never opens the next, and every item comes round again at least half a pass (`⌊N/2⌋` positions) after it last did. Each pass on its own is still an even shuffle (a random half first, each half in a random order), but consecutive passes share their halves.
  - **Why (2026-10-07):** passes used to be independent, so an item near the end of one pass could come straight back early in the next. The schedule audit showed it: over 30 days, the Movies channel (450 films, about 10 a day) aired 303 films but only 258 different ones. With halves it's 294, and a show coming back within 6 slots fell by a third (1,550 to 1,025 over every channel and 3 codes).
  - **Within a run**, what may follow what is still up to the sequence rules (§9c): the same movie or episode is held back until something else has aired, while a show may follow itself with its next episode.

**Why it replaced the derangement (2026-09-28):** the first version ported `random_derangement.py` as `LazyDerangement`: step through `(a·x + b) mod p` for a prime `p > N`, keeping values below `N`. Testing it with many codes showed:
- `b` only moves the starting point, so a channel had just `p − 1` different show loops (12 on a 12-show channel), whatever the code.
- Each order steps by a fixed amount, so the first two shows almost decide the rest; some codes gave plain title order, and show 0 almost never came first.
- Commercials reused the shows' `a` and `b`, so their order was a slow climb through the pool.

A Feistel network has none of those limits, but with 4 rounds it was uneven over small domains, so it now has 12 rounds, and channels of 10 or fewer use Fisher–Yates, which is exact. After the change every tested size matched a perfect shuffle: every order of up to 9 items appears equally often, items land evenly across positions, and 20 million codes gave the number of distinct 12-show loops a perfect shuffle would. With 40 or more shows the limit is the code itself: 2⁵⁰ different schedules per channel. `LazyDerangement` and `Primes` were removed on 2026-10-07; they're in the history before then.

**How it's used (`ShuffledShows`, id `shuffled-shows`; the film-only channels and custom channels use it, and `shuffled-mix` uses its order for each side, §9):**
- **Show IDs:** each show or movie on a channel gets a numeric ID, its index among the channel's series sorted by title.
- **Order:** each pass plays every show once, in that pass's shuffle. On pass `k`, a show plays its episode `k`, wrapping round, so each show advances one episode per pass.
- **Episodes only go forwards within a run.** The one exception: after a show's final episode, its next appearance cycles back to the pilot (its first available episode). Movies are exempt.
- **Spacing:** a show's next episode comes after N shows on average, and never fewer than ⌊N/2⌋ (the passes' halves). Where two passes meet, the show that closed one never opens the next, so on a channel of two shows they simply alternate.
- **Other strategies:** Random Shuffle uses `ShuffledOrder.Passes` over every item; Series Round Robin uses one `ShuffledOrder` for its fixed turn order.

**The schedule code (`ScheduleCode`):**
- **Format:** 10 Crockford base32 characters (`XXXXX-XXXXX`, 50 bits). It's shown and editable in Settings; the first launch picks a random one.
- **How it becomes each channel's shuffle:**
  1. `code ↔ value` is one-to-one.
  2. `value` + the channel's seed from `channels.json` gives a per-channel key, the intermediate integer (SplitMix64 mixing).
  3. The key seeds the channel's `ShuffledOrder.Passes` (and every other random choice on the channel).
- **Scope:** one code drives every channel, and every other random choice (other strategies, commercial breaks) too.
- **Sharing:** two Apple TVs with the same code, library and `channels.json` show the same programmes at the same time. That was checked on the simulator: the same code gave an identical guide across relaunches, and a different code a different one.

**Runs:** each run, from one day boundary to the next, is filled back to back from one stream, so nothing repeats or is skipped within a run. Looking up a moment fills at most one run, about a day of programmes, whatever the library size. Where runs meet, once a day, one programme may repeat or be skipped.

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
| `CustomChannelsMakeSense` | line-up check | A custom channel has a name of at most 60 characters and at most 20 conditions, each naming something (years from 1 to 9999), however it arrived. |
| `SetTimesNeedTheirChannel` | line-up check | Set times belong to a channel in the line-up, one set per channel. |

**How the sequence rules are kept.** Streams go through `RuledStream`: an item a rule rejects waits and airs as soon as it may, so nothing is dropped and the order moves as little as possible. Three places need more than that, and each is handled without chaining one run to the next:
- **Where runs meet.** Each run is laid out on its own; only its *join* depends on the run before, and never changes what it takes from the strategy. If the run's first programme mustn't follow the last one before it, a programme the rules allow takes its slot. The slot keeps its times, so the stand-in is one that fills it as the programme it replaces did (padded to the same end), or failing that the longest that fits: never a half-hour episode in a film's two hours, followed by an hour and a half of commercials. Failing any stand-in, the first slots are left out until one may follow, and their time is a break after the last programme. So every walk (from any starting run) gives the same schedule.
- **Next to a set time.** The shared schedule's programme just before a set time, or still on after it, is swapped for a stand-in that fits its slot if the rules don't allow it next to the set programme. If none fits, that part of it becomes a break instead. Only that slot changes.
- **Set times themselves.** A set time is left out that day if it would overlap the one before it, or if it's the same programme straight after it. Two set times of the same film close together are the viewer's choice, and may air with only a break between.
A channel whose shuffle has only one programme can't avoid repeating it: there, the rules give way.

**Programmes at set times: an overlay (changed 2026-09-28).** Set times name series or items and local times, with optional `days` (weekdays or dates) and `exclusive`, each read in its own time zone. They come from a channel's `fixed` list in `channels.json` (with the channel's `timeZone`), or from a household's `SetTimes`, made on the editing page for any channel.

The first version wove set times into the schedule: runs became local days and each set time a hard edge. That moved everything around it, so two households sharing a schedule code, one with a set time, agreed on only about 11% of moments (0% with `exclusive`). Now there are two layers:
- The **shared schedule** comes from the code and the channel alone, in uniform runs, exactly as without set times.
- Each set time is a **window**, from its time to the end of its programme's slot. Inside it, its programme is on, with its own breaks. Outside every window, the shared schedule is on: a programme cut by a window's start stops there, and one still on at its end is joined partway through (`mediaOffset`), as when changing channel.
- The only other change is **covering**: an `exclusive` programme's other airings, and a shared programme the rules don't allow next to an adjacent set time, get a stand-in that fits their slot. Stand-ins are searched from a point picked from the channel's key and the slot, so they vary from slot to slot while every walk picks the same one.
- A set time names a series or film. Shared by code with a household whose library lacks it, it never airs there; Settings says "Not in your library".

So outside the windows and covered slots, every household with the same code sees the same programme at the same point (tested with random channels in `RandomChannelTests`). A series' episode at each set time comes from counting its airings since the channel's first day from the calendar, so any day is found without replaying the ones before. Tuning still walks at most two days.

A household's set times on one channel are a `SetTimes`, saved in `AppPreferences` (§3) packed as a short code (the channel number, time zone and set times, in Crockford base32 with a check byte, through `CodeWriter`/`CodeReader`). Codes were typed between Apple TVs until 2026-10-01; now sharing is copying the editing page's JSON.

**Custom channels.** A channel the viewer makes (`CustomChannel`): a name, a number from 20 to 99, episodes, movies or both, a rule of up to 20 conditions on genres, series, tags, studios (added 2026-10-26, kind 4 in the code; an older app rejects a code with one) and years, each joined as *any of*, *all of* or *none of* (changed 2026-10-01; it was one rule), half-hour slots and commercials (both on by default). The strategy, seed (1000 + the number) and filler take the defaults. The rule becomes a line-up source through the combining sources `all-of`, `any-of` and `not` (`CombinedSources.swift`), which `channels.json` can use directly too, nested to any depth. Custom channels are saved in `AppPreferences` (§3) packed as version 2 codes (the conditions; version 1 codes, with one rule, still read), and a saved one whose number a newer bundled line-up takes is left out rather than breaking the line-up.

**Where they're made (decided 2026-10-01).** Custom channels and set times are made only on the **editing page** (`EditingPage`, §3), in a browser on the home network, off by default; Settings lists them read-only. The Apple TV's own editors were removed: picking from thousands of tags with a remote froze them, and combined rules are slow to build with one. The codes typed between Apple TVs went with them; the page's JSON tab (`EditingDocument`) is how channels are shared. The page previews a channel (how many programmes match, and its next three hours) by asking the Apple TV, which works it out off the main thread with no server calls.

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
- **Station card, then a fade (`upNextLead`, 15 s):** no commercial plays into the last 15 seconds of a break. In a break that had commercials, they're the station card (`WatchModel.stationCard`, drawn by the app's `StationCard`): "You're watching" the channel, the animated wordmark and colour bars, and the Up next details, over 15 seconds of music (`App/GregularTV/Audio/station-card.m4a`, synthesised by `scripts/make-station-music.py`; it starts partway when the card does, so it always ends as the programme starts). Any other gap (commercials off, past a break's 20 minutes of commercials, too short for any) keeps the plain "Up next" card, unchanged and silent. The last commercial fades out (0.5 s) into the card, which fades in (0.5 s); 1.2 s before the programme the card fades to black, holds, and the programme fades in.
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
- **The programme's quality** (2026-10-26; until then commercials were always asked for with no cap, on the assumption that clips are short and low-bitrate): a break's clips play at its programme's cap and stereo sound (`ProgrammeSettings.forBreak`), so on a slow connection a large clip no longer stalls a break, at the cost of re-encoding any clip above the cap. Not in VLC, never with a speed test (a clip is over before one helps; the programme's measurement covers the connection), and never refused for being re-encoded with under 3 minutes left. A clip whose conversion can't keep up asks for less for the rest of its break, never for its programme. Every clip plays: one the device can't play as it is (`PlaybackSource.reencodesVideo`, e.g. an unsupported codec) is converted by the server, exactly as a programme would be (2026-10-06; until then such clips were skipped and their time left blank). A clip as it is, or only remuxed, costs the server almost nothing.
- **Stall watchdog:** counts only forward progress, and restarts for each new item, so a stream stuck jittering in place is caught after 30 s.
- **Commercials switch:** Settings › Commercials › "Play commercials" (on by default, saved with the other preferences). Off rebuilds the channels with `playsCommercials: false`: every break is blank airtime with the "Up next" card and banner. The clips are still fetched and kept out of the programmes, so programme times are identical either way and everyone with the same code stays in step (tested over a week of schedule). Changing it re-tunes the current channel.
- **Settings:** with diagnostics on, Settings says what was found, for example "42 commercials from “Commercials”", or that the library is missing, not visible to this user, or not yet scanned.
- **Best clips:** short MP4s (H.264 video, AAC audio) at a modest bitrate (1080p at 5 Mbps or less). Those play as-is, so they start instantly and cost the server nothing. Large trailers (4K, or high bitrate) either need more bandwidth than a remote connection has or must be re-encoded.

## 10. Milestones

A record of what was built and checked, in order. Details like the remote controls have changed since; README describes the app as it is now.

1. ✅ **Core package + tests** (no UI): models, `SeededRandom`, `ChannelSchedule`, 4 strategies, and the shared strategy test suite. Runs with `swift test` on the Mac.
2. ✅ **Jellyfin client:** auth (Quick Connect + password), item queries, `PlaybackInfo`/stream URLs, the credential store (now `KeychainStore`) and `AppPreferences`. Tested against a mock server, and checked live against Jellyfin 10.11.1 on 2026-09-23: sign-in, a 5,927-item library, all 13 default channels, HLS stream URLs, stopping transcodes, and sign-out. (The Keychain test runs in the app's own tests, since milestone 3.)
3. ✅ **Playback MVP:** the tvOS app (`App/GregularTV.xcodeproj`). Sign-in with Quick Connect or a password (with no http/https typed, it tries https, then http), loading the library (pages fetched in parallel), and one channel (the last watched, or the lowest-numbered). It tunes in live, queues the next programme 30 s ahead, shows a card during padding, and pause jumps back to live. It re-tunes if more than 60 s behind live. Failures retry with backoff (5 s up to 60 s), and startup errors retry every 30 s. The Keychain test runs in the app's own tests.
   - Verified on the simulator against the real server (2026-09-23): sign-in, restoring the saved sign-in, joining live mid-programme, the banner, pause then jump to live, recovering by itself after a server outage, and the seamless hand-off to the next programme. The hand-off was tested with the `-handoffTest` debug flag.
   - Added during testing:
     - **Streaming quality:** Auto, plus fixed caps from Maximum down to 480p, in a settings screen opened by clicking the remote. That screen also has Sign Out.
     - **Stall watchdog:** 30 s with no progress counts as a failure and retries.
     - **Debug-build diagnostics line:** player state, how far behind live, and Jellyfin's transcode reasons.
   - **How Auto works:** a cap below a file's own bitrate makes the server re-encode it, far more work than sending the file, and on a CPU-limited server such as a Raspberry Pi, more than it can do in real time. So Auto asks for the original, with no cap and no speed test, just as Maximum does, until a programme has trouble on the connection: a 30 s stall, falling a minute behind live, or a failure that's the connection's (`ErrorKind.connection`: a `ConnectionFailure` such as VLC's dropped connection or the browser's network error, or a lost URL connection, including one AVFoundation wraps; or a timeout while the video plays). A file the player can't show, the server's own error, or the server taking too long to answer when asked for the stream (busy, not a connection that can't carry it) is just retried: a lower quality wouldn't help. Then it measures *before* retrying (the retry waits anyway), with nothing else downloading, and caps that programme at 70% of the measurement. The cap is for that programme only (every part of it): the next programme, or changing channel, starts again with the original. Until 2026-10-25 the cap lasted the whole session, across programmes and channels, and any failure set it, so one blip could leave Auto re-encoding for the evening while Maximum never did. (A re-encoded programme's trouble is the server's processor, not the connection: it steps down instead, below.) While capped, the speed test (`/Playback/BitrateTest`, with a warm-up request first, then `SpeedTest`: downloads of 256 KB, 1 MB, 4 MB and 12 MB, stopping at the first that takes 0.75 s, so a few seconds on any connection; until 2026-10-26 it was always 3 MB, most of a minute at 1 Mbps, which the retry waited for) runs in the background about 20 s after the programme (re)starts, if the cap is over 10 minutes old, and can raise the cap but never lower it: a test run while video downloads understates the connection. Before 2026-10-01, Auto started at 8 Mbps and let any background test lower the cap, which could make a Pi re-encode most files. With a fixed quality, no speed test runs, and switching away from Auto cancels one that's pending. Package and app tests check this by recording requests.
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
   - `scripts/privacy-check.sh` runs as the app's first build phase (with script sandboxing off for the app target, because it reads the source tree) and as a `swift test` test. It fails on persistence and logging APIs outside `KeychainStore.swift`, `AppPreferences.swift` and `HTTPTransport.swift`. It was checked by adding a violating file: the build failed and named the line.
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
   - Every on-screen error goes through `FriendlyError`, which gives plain messages, because the system's own error text can name the server's host. App tests check this. What kind of trouble an error is (signed out, the connection, a slow or unreachable server, a certificate, the server's own error) is decided once, in `ErrorKind`, which both `FriendlyError` and the player's retries use.
   - Branded launch and loading screens. Version 1.0.

## 11. Testing strategy

- **Determinism:** same seed + items + time → identical `nowPlaying` across runs, and when the input item order is shuffled first. We sort the input by a stable key before calling the strategy, so Jellyfin's API ordering can't change the schedule.
- **Engine:** run boundaries, times before the epoch, a single-item channel, padding and run-end gaps, and sequences carrying on across runs. A laziness test checks that tuning into a 20,000-episode channel pulls at most two days of programmes (the run, and the one before for what aired last). All the maths is in milliseconds from the epoch; only where runs start uses the Pacific calendar, which a test checks across both daylight-saving changes.
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
- **Custom channels** are made on the editing page (off by default) and saved as their codes: privacy option (a), allowing exactly this in `AppPreferences` (§3, §9c).
- **Programmes at set times** are built, in `channels.json` and in Settings for any channel (§9c).
- **Set times are an overlay** on the shared schedule, so households sharing a code stay in step outside their set times; a household's set times are shared by copying the editing page's JSON (§9c).

**Decided (2026-10-26): feeds**
- **Sharing by link, not RSS:** the editing page's own JSON, with a name, a line, a picture and a time zone, at any https link (README, *Feeds*; §3).
- **A feed brings its own channels and set times on them, nothing else** (never the schedule code, never anything on bundled or the viewer's channels), in a block of ten numbers the viewer picks, at most 10 channels.
- **Updates take one tap** (*Get Update*): a dot on Settings, short *what's new* lines. The first version is taken when following. Feed channels are read-only; *Make a Copy* makes one the viewer's own. Unfollowing removes everything the feed brought. A link that stops working keeps the version accepted and is marked expired.
- **Checked when the app opens, then every 6 hours** while it runs. No proxy for the web: a host must allow CORS.
- **Backlog:** a per-feed switch, off by default, letting a feed set times on the viewer's channels, with clash rules (TODO.md).

**Decided (2026-10-26): commercials follow their programme's quality**
- **No special treatment:** commercials were asked for with no cap, on the assumption that clips are short and low-bitrate, which doesn't always hold. Now a break plays at its programme's cap (the quality setting, its fix, or Auto's measurement) and with its stereo sound; a clip above the cap is re-encoded (§9a).
- **What stays different, and why:** never in VLC (one player per clip); never a speed test (a clip is over before one helps); no 3-minute rule for re-encodes (it would blank every break). A clip's trouble asks for less within its break only, so a film never re-encodes because of its mid-roll.

**Prerequisites**
- ✅ Xcode 27 with the licence accepted, the tvOS 27 SDK, and the tvOS 27 simulator runtime (verified 2026-09-23). `GregularCore` and `GregularJellyfin` tests pass on macOS and on the Apple TV 4K simulator.
- A reachable Jellyfin server (10.9 or later) for milestone 2 onward. A throwaway Docker instance with a few sample files works well for development.
