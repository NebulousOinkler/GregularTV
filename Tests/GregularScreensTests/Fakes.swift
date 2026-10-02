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
        let preferences = AppPreferences.testing()
        preferences.streamingQuality = .hd10
        return ChannelSurfer(channels: channels, startingWith: channels[0], streams: FakeStreams(),
                             preferences: preferences, decks: FakeDeck.pair())
    }

    /// An app named "Test Device", signed in to whatever `store` holds,
    /// playing on fake decks.
    @MainActor static func app(store: InMemoryCredentialStore = InMemoryCredentialStore()) -> AppModel {
        AppModel(deviceName: "Test Device", store: store, preferences: AppPreferences.testing(), makeDecks: FakeDeck.pair)
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
