import Foundation
import GregularCore
import Testing
@testable import GregularScreens

/// Auto quality, on decks with no video: the original until playback has
/// trouble, then a cap from a speed test made with nothing playing.
@MainActor @Suite(.serialized)
struct AutoCapTests {
    /// A server whose speed test says `measured`, recording the cap each
    /// stream was asked for.
    final class MeasuredStreams: StreamSource, @unchecked Sendable {
        private let lock = NSLock()
        private let measured: Int
        private var asked: [Int] = []
        private var tests = 0

        init(measured: Int) { self.measured = measured }

        var caps: [Int] { lock.withLock { asked } }
        var speedTests: Int { lock.withLock { tests } }

        func stream(for itemID: String, maxBitrate: Int) async throws -> MediaStream {
            lock.withLock { asked.append(maxBitrate) }
            return MediaStream(url: URL(string: "https://tv.invalid/\(itemID)")!, delivery: .original)
        }
        func release(_ stream: MediaStream) async {}
        func measureBandwidth() async throws -> Int {
            lock.withLock { tests += 1 }
            return measured
        }
    }

    /// Auto, 10 minutes into an hour-long film.
    private func player(_ streams: MeasuredStreams) throws -> ChannelPlayer {
        let items = [MediaItem(id: "m", kind: .movie, name: "Film", duration: 3600)]
        let schedule = try #require(try ChannelSchedule.testing(epoch: Date.now.addingTimeInterval(-600), items: items).first)
        return ChannelPlayer(schedule: schedule, streams: streams, quality: .auto, decks: FakeDeck.pair())
    }

    @Test func autoAsksForTheOriginalWithNoSpeedTest() async throws {
        let streams = MeasuredStreams(measured: 10_000_000)
        let player = try player(streams)
        player.start()
        try await Fixture.settle(player)
        #expect(streams.caps == [StreamingQuality.maximumBitrate],
                "No cap: a lower one would make the server re-encode")
        #expect(streams.speedTests == 0)
        player.stop()
    }

    @Test func fallingBehindLiveMeasuresThenCaps() async throws {
        let streams = MeasuredStreams(measured: 10_000_000)
        let player = try player(streams)
        player.start()
        let deck = try await Fixture.playingDeck(player)
        deck.seek(to: 300)   // as if buffering had left it 5 minutes behind live
        try await waitUntil(3) { streams.caps.count == 2 }
        #expect(streams.speedTests == 1, "Measured before loading again")
        #expect(streams.caps.last == 7_000_000, "70% of the measurement")
        try await Fixture.settle(player)
        player.stop()
    }
}
