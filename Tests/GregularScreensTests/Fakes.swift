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
        let epoch = ISO8601DateFormatter().string(from: Date.now.addingTimeInterval(-elapsed))
        let json = [1, 2].map {
            #"{ "number": \#($0), "name": "C\#($0)", "source": { "type": "all" }, "strategy": "derangement", "seed": \#($0), "epoch": "\#(epoch)" }"#
        }.joined(separator: ",")
        let items = (1...3).map { MediaItem(id: "m\($0)", kind: .movie, name: "Film \($0)", duration: 3600) }
        let channels = try ChannelLineup.load(from: Data("[\(json)]".utf8)).schedules(for: items)
        let preferences = AppPreferences(defaults: UserDefaults(suiteName: "ScreensTests-\(UUID())")!)
        preferences.streamingQuality = .hd10
        return ChannelSurfer(channels: channels, startingWith: channels[0], streams: FakeStreams(),
                             preferences: preferences, decks: FakeDeck.pair())
    }

    @MainActor static func settle(_ player: ChannelPlayer) async throws {
        for _ in 0..<200 where player.status != .playing { try await Task.sleep(for: .milliseconds(10)) }
    }
}
