import Foundation
import GregularCore
import Testing
@testable import GregularScreens

/// A file a player can't decode, on decks with no video: each failure rules
/// out one format, the retry asks at once for something else, and it ends,
/// at worst saying the programme can't be played here.
@MainActor @Suite(.serialized)
struct UnplayableTests {
    /// A decode failure, as a deck reports it.
    struct CantDecode: UnplayableMedia {}

    private let hevc10 = MediaFormat(.video, "hevc", profile: "main 10")
    private let eac3 = MediaFormat(.sound, "eac3")
    private let safest: Set<MediaFormat> = [MediaFormat(.video, "h264"), MediaFormat(.sound, "aac")]

    @Test func eachFailureRulesOutOneFormatSoundFirst() {
        var unplayable = UnplayableFormats()
        let file = StreamContents(video: hevc10, sound: eac3)
        let first = unplayable.learn(from: file, on: .builtIn, safest: safest)
        #expect(first && unplayable.byPlayer[.builtIn] == [eac3])
        let second = unplayable.learn(from: StreamContents(video: hevc10, sound: MediaFormat(.sound, "aac")), on: .builtIn, safest: safest)
        #expect(second && unplayable.byPlayer[.builtIn] == [eac3, hevc10])
        let last = unplayable.learn(from: StreamContents(video: MediaFormat(.video, "h264"), sound: MediaFormat(.sound, "aac")),
                                    on: .builtIn, safest: safest)
        #expect(!last, "Only the safest formats: nothing's left to rule out")
        let again = unplayable.learn(from: file, on: .builtIn, safest: safest)
        #expect(!again, "What's ruled out isn't ruled out twice")
        let addOn = unplayable.learn(from: file, on: .addOn, safest: safest)
        #expect(addOn && unplayable.byPlayer[.addOn] == [eac3], "Each player is its own")
    }

    /// A server that names a different format each time can't keep the
    /// immediate retries going: there's a most per player.
    @Test func thereIsAMostPerPlayer() {
        var unplayable = UnplayableFormats()
        var learned = 0
        for n in 0..<100 where unplayable.learn(from: StreamContents(sound: MediaFormat(.sound, "made-up-\(n)")), on: .builtIn, safest: safest) {
            learned += 1
        }
        #expect(learned == UnplayableFormats.mostPerPlayer)
    }

    /// End to end: the sound, then the video, converted; then it can't be
    /// played here, until its slot ends, and isn't asked for again.
    @Test func theRetriesEndAndSaySo() async throws {
        let file = StreamContents(video: hevc10, sound: eac3)
        let streams = FakeStreams(files: ["m1": file, "m2": file, "m3": file])   // whichever film is on
        let player = try Fixture.surfer(streams: streams).player
        player.start()
        for expected in [[], [eac3], [eac3, hevc10]] as [Set<MediaFormat>] {
            let deck = try await Fixture.playingDeck(player)
            #expect(streams.ruledOut.last == expected)
            let item = try #require(deck.queue.first)
            let count = streams.ruledOut.count
            item.failure = CantDecode()
            item.hasFailed = true
            try await waitUntil(3) { streams.ruledOut.count > count || { if case .cantPlay = player.status { true } else { false } }() }
            #expect(!player.status.isFailed, "No backoff: the server isn't at fault")
        }
        guard case .cantPlay(let until) = player.status else {
            Issue.record("Expected it to say it can't be played, not \(player.status)")
            return
        }
        #expect(until == player.airing?.slotEnd && streams.ruledOut.count == 3)
        player.tune()   // as if tuning in again: it isn't asked for
        #expect(streams.ruledOut.count == 3)
        if case .cantPlay = player.status {} else { Issue.record("Still can't be played: \(player.status)") }
        // What was learned lasts the session: another channel's first request leaves them out.
        player.switchTo(player.schedule)
        try await waitUntil(3) { streams.ruledOut.count == 4 }
        #expect(streams.ruledOut.last == [eac3, hevc10])
        player.stop()
    }

    @Test func aDecodeFailureIsItsOwnKind() {
        #expect(ErrorKind(CantDecode()) == .unplayable)
    }
}
