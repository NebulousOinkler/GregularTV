import Foundation
import GregularCore
import GregularJellyfin
import Testing
@testable import GregularTV

/// Commercials never make the server re-encode video: the original file,
/// asked for with no bitrate cap (as-is or remuxed), else they're skipped.
/// They never run a speed test.
@MainActor @Suite(.serialized)
struct CommercialQualityTests {
    /// Answers PlaybackInfo with `reply`, and records every request.
    final class Server: HTTPTransport, @unchecked Sendable {
        private let lock = NSLock()
        private var log: [URLRequest] = []
        let reply: String

        init(reply: String) { self.reply = reply }

        var playbackInfos: [URLRequest] { lock.withLock { log }.filter { $0.url!.path.hasSuffix("/PlaybackInfo") } }
        var speedTests: Int { lock.withLock { log }.filter { $0.url!.path.hasSuffix("/Playback/BitrateTest") }.count }

        func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            lock.withLock { log.append(request) }
            let body = request.url!.path.hasSuffix("/PlaybackInfo") ? Data(reply.utf8) : Data()
            return (body, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
    }

    static let directPlay = #"{ "MediaSources": [{ "Id": "s", "SupportsDirectPlay": true }], "PlaySessionId": "p" }"#
    static func hls(reasons: String) -> String {
        #"{ "MediaSources": [{ "Id": "s", "SupportsDirectPlay": false, "TranscodingUrl": "/videos/ad/master.m3u8?TranscodeReasons=\#(reasons)" }], "PlaySessionId": "p" }"#
    }

    /// A channel tuned 30 seconds into a commercial break: a 20-minute
    /// episode in a 30-minute slot, the rest filled with one-minute ads.
    private func playerInABreak(server: Server, playsCommercials: Bool = true) throws -> ChannelPlayer {
        let epoch = ISO8601DateFormatter().string(from: Date.now.addingTimeInterval(-(20 * 60 + 30)))
        let json = #"[{ "number": 1, "name": "C", "source": { "type": "all" }, "strategy": "derangement", "seed": 1, "padTo": 30, "filler": "derangement", "epoch": "\#(epoch)" }]"#
        let items = [MediaItem(id: "ep", kind: .episode, name: "E", duration: 20 * 60)]
        let ads = (0..<5).map { MediaItem(id: "ad\($0)", kind: .video, name: "Ad", duration: 60) }
        let schedule = try #require(try ChannelLineup.load(from: Data(json.utf8)).schedules(for: items, fillerPool: ads, playsCommercials: playsCommercials).first)
        #expect(schedule.tune(at: .now).isInPadding || schedule.tune(at: .now).airing.isFiller, "The test needs to start in the break")
        let client = JellyfinClient(
            credentials: Credentials(serverURL: URL(string: "https://tv.invalid")!, userID: "u", accessToken: "t"),
            identity: ClientIdentity(deviceID: "test"), transport: server)
        return ChannelPlayer(schedule: schedule, streams: client, quality: .auto)
    }

    private func settle(_ server: Server) async throws {
        for _ in 0..<100 where server.playbackInfos.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        try await Task.sleep(for: .milliseconds(300))
    }

    private func caps(_ server: Server) -> [String?] {
        server.playbackInfos.map { request in
            URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "maxStreamingBitrate" }?.value
        }
    }

    @Test func aPlayableCommercialUsesTheOriginalFile() async throws {
        ChannelPlayer.backgroundMeasurementDelay = .zero
        let server = Server(reply: Self.directPlay)
        let player = try playerInABreak(server: server)
        player.tune()
        try await settle(server)
        #expect(caps(server) == [String(StreamingQuality.maximumBitrate)], "No cap, whatever the quality setting")
        #expect(server.speedTests == 0, "Even in Auto, commercials never run a speed test")
        player.stop()
    }

    @Test func aRemuxIsKeptBecauseItIsCheap() async throws {
        let server = Server(reply: Self.hls(reasons: "ContainerNotSupported,AudioCodecNotSupported"))
        let player = try playerInABreak(server: server)
        player.tune()
        try await settle(server)
        #expect(caps(server) == [String(StreamingQuality.maximumBitrate)])
        player.stop()
    }

    @Test func withCommercialsOffABreakAsksJellyfinForNothing() async throws {
        let server = Server(reply: Self.directPlay)
        let player = try playerInABreak(server: server, playsCommercials: false)
        player.tune()
        try await Task.sleep(for: .milliseconds(500))
        #expect(server.playbackInfos.isEmpty, "No commercial is requested, so no stream is opened")
        #expect(player.airing?.isFiller == false, "The banner shows the programme, not a commercial")
        guard case .betweenProgrammes = player.status else {
            Issue.record("A break with commercials off is blank, not \(player.status)")
            return
        }
        player.stop()
    }

    @Test func aCommercialThatMustBeReencodedIsSkipped() async throws {
        let server = Server(reply: Self.hls(reasons: "VideoCodecNotSupported"))
        let player = try playerInABreak(server: server)
        player.tune()
        try await settle(server)
        #expect(caps(server) == [String(StreamingQuality.maximumBitrate)], "Asked once; no lower-quality retry")
        guard case .betweenProgrammes = player.status else {
            Issue.record("A skipped commercial leaves the screen blank, not \(player.status)")
            return
        }
        // Tuning in again asks nothing more about the same clip this session.
        let asked = server.playbackInfos.count
        player.tune()
        try await Task.sleep(for: .milliseconds(300))
        #expect(server.playbackInfos.count == asked)
        player.stop()
    }
}
