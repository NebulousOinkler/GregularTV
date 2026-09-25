import Foundation
import GregularCore
import GregularJellyfin
import Testing
@testable import GregularTV

/// "Trouble with this programme?" in Settings: a lower quality for just the
/// programme on now, back to standard on a channel change or the next programme.
@MainActor @Suite(.serialized)
struct ProgrammeFixTests {
    /// Plays everything as-is (or answers with `reply`), and records the cap
    /// of every PlaybackInfo request.
    final class Server: HTTPTransport, @unchecked Sendable {
        let reply: String
        init(reply: String = HeadStartTests.directPlay) { self.reply = reply }
        private let lock = NSLock()
        private var caps: [Int] = []
        var requestedCaps: [Int] { lock.withLock { caps } }

        func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            var body = Data()
            if request.url!.path.hasSuffix("/PlaybackInfo") {
                let cap = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
                    .queryItems?.first { $0.name == "maxStreamingBitrate" }?.value.flatMap { Int($0) }
                lock.withLock { caps.append(cap ?? 0) }
                body = Data(reply.utf8)
            }
            return (body, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
    }

    /// Two channels of hour-long programmes, ten minutes into one, at a fixed
    /// 10 Mbps quality. (A fixed point in the programme, so tests don't depend
    /// on the time of day.)
    private func surfer(_ server: Server) throws -> ChannelSurfer {
        let epoch = ISO8601DateFormatter().string(from: Date.now.addingTimeInterval(-600))
        let json = [1, 2].map {
            #"{ "number": \#($0), "name": "C\#($0)", "source": { "type": "all" }, "strategy": "derangement", "seed": \#($0), "epoch": "\#(epoch)" }"#
        }.joined(separator: ",")
        let items = (1...3).map { MediaItem(id: "m\($0)", kind: .movie, name: "M\($0)", duration: 3600) }
        let channels = try ChannelLineup.load(from: Data("[\(json)]".utf8)).schedules(for: items)
        let preferences = AppPreferences(defaults: UserDefaults(suiteName: "ProgrammeFixTests-\(UUID())")!)
        preferences.streamingQuality = .hd10
        let client = JellyfinClient(
            credentials: Credentials(serverURL: URL(string: "https://tv.invalid")!, userID: "u", accessToken: "t"),
            identity: ClientIdentity(deviceID: "test"), transport: server)
        return ChannelSurfer(channels: channels, startingWith: channels[0], streams: client, preferences: preferences)
    }

    private func settle(_ player: ChannelPlayer) async throws {
        for _ in 0..<100 where player.status != .playing { try await Task.sleep(for: .milliseconds(10)) }
    }

    @Test func stepDownRestartsOneStepLowerThenAnother() async throws {
        let server = Server()
        let player = try surfer(server).player
        player.tune()
        try await settle(player)
        player.setProgrammeFix(.stepDown)
        try await settle(player)
        player.setProgrammeFix(.stepDown)   // pressed again: one more step
        try await settle(player)
        #expect(server.requestedCaps == [10_000_000, 4_000_000, 1_500_000])
        #expect(player.programmeFix == .stepDown)
        #expect(player.streamDescription?.hasPrefix("This programme only") == true)
        player.stop()
    }

    @Test func hd720AndBackToStandard() async throws {
        let server = Server()
        let player = try surfer(server).player
        player.tune()
        try await settle(player)
        player.setProgrammeFix(.hd720)
        try await settle(player)
        player.setProgrammeFix(.standard)
        try await settle(player)
        #expect(server.requestedCaps == [10_000_000, 4_000_000, 10_000_000])
        #expect(player.programmeFix == .standard)
        player.stop()
    }

    @Test func theNextProgrammeGoesBackToStandard() async throws {
        let server = Server()
        // An hour-long programme with two seconds left.
        let epoch = ISO8601DateFormatter().string(from: Date.now.addingTimeInterval(-3598))
        let json = #"[{ "number": 1, "name": "C", "source": { "type": "all" }, "strategy": "derangement", "seed": 1, "epoch": "\#(epoch)" }]"#
        let items = (1...3).map { MediaItem(id: "m\($0)", kind: .movie, name: "M\($0)", duration: 3600) }
        let schedule = try #require(try ChannelLineup.load(from: Data(json.utf8)).schedules(for: items).first)
        let client = JellyfinClient(
            credentials: Credentials(serverURL: URL(string: "https://tv.invalid")!, userID: "u", accessToken: "t"),
            identity: ClientIdentity(deviceID: "test"), transport: server)
        let player = ChannelPlayer(schedule: schedule, streams: client, quality: .hd10)
        player.tune()
        try await settle(player)
        player.setProgrammeFix(.hd720)
        try await settle(player)
        #expect(player.programmeFix == .hd720)
        try await Task.sleep(for: .seconds(2.5))
        player.tune()   // now on the next programme
        try await settle(player)
        #expect(player.programmeFix == .standard)
        #expect(server.requestedCaps.last == 10_000_000)
        player.stop()
    }

    @Test func changingChannelGoesBackToStandard() async throws {
        let server = Server()
        let surfer = try surfer(server)
        let player = surfer.player
        player.tune()
        try await settle(player)
        player.setProgrammeFix(.hd720)
        try await settle(player)
        player.switchTo(surfer.channels[1])
        try await settle(player)
        #expect(player.programmeFix == .standard)
        #expect(server.requestedCaps.last == 10_000_000)
        player.stop()
    }

    /// Jellyfin re-encodes, from a server that doesn't exist, so every attempt
    /// fails. Retries come 5 s, then 10 s, after each failure.
    @Test func aReencodeThatFailsRetriesAt720pThenLower() async throws {
        let server = Server(reply: HeadStartTests.hls(reasons: "VideoCodecNotSupported"))
        let player = try surfer(server).player
        func waitFor(requests: Int, thenFix fix: ChannelPlayer.ProgrammeFix) async throws {
            for _ in 0..<200 {
                if server.requestedCaps.count >= requests, case .failed = player.status, player.programmeFix == fix { return }
                try await Task.sleep(for: .milliseconds(100))
            }
            Issue.record("Expected request \(requests) to fail with \(fix), not \(player.status), \(player.programmeFix)")
        }
        player.start()
        try await waitFor(requests: 1, thenFix: .hd720)
        try await waitFor(requests: 2, thenFix: .stepDown)
        for _ in 0..<150 where server.requestedCaps.count < 3 { try await Task.sleep(for: .milliseconds(100)) }
        #expect(Array(server.requestedCaps.prefix(3)) == [10_000_000, 4_000_000, 1_500_000])
        player.stop()
    }
}
