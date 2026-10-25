import Foundation
import GregularCore
import GregularJellyfin
import Testing
@testable import GregularScreens

/// A `PlayerDeck` with no video at all: it records what it's told, so the
/// player's decisions can be checked without Apple TV (or a browser).
@MainActor final class FakeDeck: PlayerDeck {
    final class Item: PlayerItem {
        let url: URL
        let player: MediaStream.Player
        let start: TimeInterval
        let end: TimeInterval
        /// How far ahead the player was asked to buffer, or nil for its default.
        let bufferAhead: TimeInterval?
        var hasFailed = false
        var failure: (any Error)?
        var bufferedAhead: TimeInterval = 60
        var bufferedInAll: TimeInterval = 60
        init(url: URL, player: MediaStream.Player, start: TimeInterval, end: TimeInterval, bufferAhead: TimeInterval?) {
            self.url = url
            self.player = player
            self.start = start
            self.end = end
            self.bufferAhead = bufferAhead
        }
    }

    private(set) var queue: [Item] = []
    private(set) var seeks: [TimeInterval] = []
    var pausesAtItemEnd = false
    var volume: Float = 1
    private(set) var state: PlayerDeckState = .paused
    var position: TimeInterval = 0

    static func pair() -> [any PlayerDeck] { [FakeDeck(), FakeDeck()] }

    func makeItem(url: URL, on player: MediaStream.Player, from start: TimeInterval, to end: TimeInterval,
                  bufferAhead: TimeInterval?) -> any PlayerItem {
        Item(url: url, player: player, start: start, end: end, bufferAhead: bufferAhead)
    }

    var currentItem: (any PlayerItem)? { queue.first }
    func contains(_ item: any PlayerItem) -> Bool { queue.contains { $0 === item } }
    func append(_ item: any PlayerItem) { if let item = item as? Item { queue.append(item) } }
    func removeAll() { queue = [] }
    func advance() { if !queue.isEmpty { queue.removeFirst() } }
    func play() { state = .playing }
    /// The current item reaches its end: with `pausesAtItemEnd`, the deck
    /// holds on it, paused; otherwise it moves on to the next.
    func finishCurrentItem() {
        if pausesAtItemEnd { state = .paused } else { advance() }
    }
    func pause() { state = .paused }
    /// Runs out of video while playing, until it's played or paused again.
    func startBuffering() { state = .waiting }
    func seek(to seconds: TimeInterval) {
        seeks.append(seconds)
        position = seconds
    }
    var activity: String {
        switch state {
        case .playing: "Playing"
        case .paused: "Paused"
        case .waiting: "Buffering"
        }
    }
}

/// A server for the player's tests. Each item's file plays as it is on every
/// player the device has (`players`), except:
/// - `converting`: it re-encodes them (as for the quality cap);
/// - `addOnOnly`: only the add-on player plays them as they are; it
///   repackages them for any other;
/// - `soundConverting`: only the add-on player plays them as they are; it
///   converts their sound for any other;
/// - with `streaming`, it repackages everything the built-in player would
///   otherwise play as it is.
///
/// Each stream it serves itself is in a session of its own. The first stream
/// asked for fails with `failingFirst`, if given. A stream converted for the
/// built-in player has at most `mostSoundChannels`. Its speed test says
/// `measured`. It records each request, and each stream it was told is
/// still wanted.
final class FakeStreams: StreamSource, @unchecked Sendable {
    private let lock = NSLock()
    private let measured: Int
    private let converting: Set<String>
    private let streaming: Bool
    private let addOnOnly: Set<String>
    private let soundConverting: Set<String>
    private var failingFirst: (any Error)?
    let players: [MediaStream.Player]
    let mostSoundChannels: Int
    private var requests: [StreamRequest] = []
    private var log: [String] = []
    private var tests = 0
    private var kept: [String] = []

    init(measured: Int = 50_000_000, converting: Set<String> = [], streaming: Bool = false,
         players: [MediaStream.Player] = [.builtIn], addOnOnly: Set<String> = [], soundConverting: Set<String> = [],
         mostSoundChannels: Int = 6, failingFirst: (any Error)? = nil) {
        self.measured = measured
        self.converting = converting
        self.streaming = streaming
        self.addOnOnly = addOnOnly
        self.soundConverting = soundConverting
        self.mostSoundChannels = mostSoundChannels
        self.failingFirst = failingFirst
        self.players = players
    }

    /// Each stream's cap, in order.
    var caps: [Int] { lock.withLock { requests.map(\.maxBitrate) } }
    /// For each stream asked for, the players asked about, in order.
    var playersAsked: [[MediaStream.Player]] { lock.withLock { requests.map(\.players) } }
    /// For each stream asked for, whether it was with stereo sound.
    var stereoAsked: [Bool] { lock.withLock { requests.map(\.stereoSound) } }
    var speedTests: Int { lock.withLock { tests } }
    /// What it was asked, in order: "speed test", or "<item ID> at <cap>".
    var events: [String] { lock.withLock { log } }
    /// The sessions kept going, in order.
    var keptAlive: [String] { lock.withLock { kept } }

    func stream(for itemID: String, _ request: StreamRequest) async throws -> MediaStream {
        lock.withLock {
            requests.append(request)
            log.append("\(itemID) at \(request.maxBitrate)")
        }
        if let failure = lock.withLock({ () -> (any Error)? in defer { failingFirst = nil }; return failingFirst }) { throw failure }
        let url = URL(string: "https://tv.invalid/\(itemID)")!
        let addOnOnly = addOnOnly.contains(itemID) || soundConverting.contains(itemID)
        let asItIs = request.players.first { $0 == .addOn || !addOnOnly }
        let delivery: MediaStream.Delivery =
            converting.contains(itemID) ? .reencoded
            : asItIs == nil ? (soundConverting.contains(itemID) ? .soundConverted : .repackaged)
            : streaming && asItIs == .builtIn ? .repackaged
            : .original
        return MediaStream(url: url, delivery: delivery, player: delivery.isStreamed ? .builtIn : asItIs ?? .builtIn,
                           sessionID: delivery.isStreamed ? "session-\(itemID)" : nil)
    }
    func release(_ stream: MediaStream) async {}
    func keepAlive(_ stream: MediaStream) async {
        if let session = stream.sessionID { lock.withLock { kept.append(session) } }
    }
    func measureBandwidth() async throws -> Int {
        lock.withLock {
            tests += 1
            log.append("speed test")
        }
        return measured
    }
}

enum Fixture {
    /// Two channels of hour-long films, `elapsed` seconds into one.
    @MainActor static func surfer(elapsed: TimeInterval = 600, streams: FakeStreams = FakeStreams()) throws -> ChannelSurfer {
        let items = (1...3).map { MediaItem(id: "m\($0)", kind: .movie, name: "Film \($0)", duration: 3600) }
        let channels = try ChannelSchedule.testing([1, 2], epoch: Date.now.addingTimeInterval(-elapsed), items: items)
        let preferences = AppPreferences.testing()
        preferences.streamingQuality = .hd10
        return ChannelSurfer(channels: channels, startingWith: channels[0], streams: streams,
                             preferences: preferences, decks: FakeDeck.pair())
    }

    /// An app named "Test Device", signed in to whatever `store` holds,
    /// playing on fake decks.
    /// - Parameter firstLaunch: as if just installed (no preferences yet),
    ///   which forgets what's in `store`; otherwise an app launched before.
    /// - Parameter transport: the network; by default, with no server on it.
    @MainActor static func app(store: InMemoryCredentialStore = InMemoryCredentialStore(), firstLaunch: Bool = false,
                               transport: any HTTPTransport = NoServer(),
                               specialModes: SpecialModeRegistry = SpecialModeRegistry()) -> AppModel {
        let preferences = AppPreferences.testing()
        if !firstLaunch { preferences.scheduleCode = .standard }
        return AppModel(deviceName: "Test Device", formats: .appleTV, transport: transport, store: store,
                        preferences: preferences, makeDecks: FakeDeck.pair, specialModes: specialModes)
    }

    @MainActor static func settle(_ player: ChannelPlayer) async throws {
        try await waitUntil(2) { player.status == .playing }
    }

    /// Waits for `player` to play, then the deck it's playing on.
    @MainActor static func playingDeck(_ player: ChannelPlayer) async throws -> FakeDeck {
        try await settle(player)
        return try #require(player.decks[player.activeIndex] as? FakeDeck)
    }
}

/// The network, with no server on it: every request fails at once, so app
/// tests never reach a real network (and run the same on every platform).
struct NoServer: HTTPTransport {
    struct Unreachable: Error {}

    func send(_ request: ServerRequest) async throws -> ServerReply {
        throw Unreachable()
    }
}
