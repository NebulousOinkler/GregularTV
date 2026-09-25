import Foundation
import GregularCore
@testable import GregularScreens

/// A `PlayerDeck` with no video at all: it records what it's told, so the
/// player's decisions can be checked without Apple TV (or a browser).
@MainActor final class FakeDeck: PlayerDeck {
    final class Item: PlayerItem {
        let url: URL
        let start: TimeInterval
        let end: TimeInterval
        var hasFailed = false
        var failure: (any Error)?
        var bufferedAhead: TimeInterval = 60
        init(url: URL, start: TimeInterval, end: TimeInterval) {
            self.url = url
            self.start = start
            self.end = end
        }
    }

    private(set) var queue: [Item] = []
    private(set) var seeks: [TimeInterval] = []
    var pausesAtItemEnd = false
    var volume: Float = 1
    private(set) var state: PlayerDeckState = .paused
    var position: TimeInterval = 0

    static func pair() -> [any PlayerDeck] { [FakeDeck(), FakeDeck()] }

    func makeItem(url: URL, from start: TimeInterval, to end: TimeInterval, bufferAhead: TimeInterval?) -> any PlayerItem {
        Item(url: url, start: start, end: end)
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
    func seek(to seconds: TimeInterval) {
        seeks.append(seconds)
        position = seconds
    }
    func diagnostics(behindLive: TimeInterval, conversionReasons: String?, preloaded: (any PlayerItem)?) -> String {
        "fake"
    }
}

/// A server that plays everything as the original file.
struct FakeStreams: StreamSource {
    func stream(for itemID: String, maxBitrate: Int) async throws -> MediaStream {
        MediaStream(url: URL(string: "https://tv.invalid/\(itemID)")!, delivery: .original)
    }
    func release(_ stream: MediaStream) async {}
    func measureBandwidth() async throws -> Int { 50_000_000 }
}

enum Fixture {
    /// Two channels of hour-long films, `elapsed` seconds into one.
    @MainActor static func surfer(elapsed: TimeInterval = 600) throws -> ChannelSurfer {
        let items = (1...3).map { MediaItem(id: "m\($0)", kind: .movie, name: "Film \($0)", duration: 3600) }
        let channels = try ChannelSchedule.testing([1, 2], epoch: Date.now.addingTimeInterval(-elapsed), items: items)
        let preferences = Self.preferences()
        preferences.streamingQuality = .hd10
        return ChannelSurfer(channels: channels, startingWith: channels[0], streams: FakeStreams(),
                             preferences: preferences, decks: FakeDeck.pair())
    }

    /// Preferences of their own, so tests never share (or touch the app's).
    static func preferences() -> AppPreferences {
        AppPreferences(defaults: UserDefaults(suiteName: "ScreensTests-\(UUID())")!)
    }

    @MainActor static func settle(_ player: ChannelPlayer) async throws {
        try await waitUntil(2) { player.status == .playing }
    }
}

extension ChannelSchedule {
    /// Test channels numbered `numbers` (each seeded with its number), all
    /// playing `items`, with `ads` as commercials if there are any.
    static func testing(_ numbers: [Int] = [1], strategy: String = "derangement", epoch: Date? = nil,
                        padTo: Int? = nil, items: [MediaItem], ads: [MediaItem] = [],
                        playsCommercials: Bool = true) throws -> [ChannelSchedule] {
        let channels = numbers.map { n in
            var fields = [#""number": \#(n)"#, #""name": "C\#(n)""#, #""source": { "type": "all" }"#,
                          #""strategy": "\#(strategy)""#, #""seed": \#(n)"#]
            if let padTo { fields.append(#""padTo": \#(padTo)"#) }
            if !ads.isEmpty { fields.append(#""filler": "derangement""#) }
            if let epoch { fields.append(#""epoch": "\#(ISO8601DateFormatter().string(from: epoch))""#) }
            return "{ " + fields.joined(separator: ", ") + " }"
        }
        return try ChannelLineup.load(from: Data("[\(channels.joined(separator: ","))]".utf8))
            .schedules(for: items, fillerPool: ads, playsCommercials: playsCommercials)
    }
}

/// Waits, checking every 10 ms, until `condition` holds or `seconds` pass.
@MainActor func waitUntil(_ seconds: TimeInterval, _ condition: () -> Bool) async throws {
    let deadline = Date.now.addingTimeInterval(seconds)
    while !condition(), Date.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
}

extension ChannelPlayer.Status {
    var isFailed: Bool { if case .failed = self { true } else { false } }
    var isBetweenProgrammes: Bool { if case .betweenProgrammes = self { true } else { false } }
}
