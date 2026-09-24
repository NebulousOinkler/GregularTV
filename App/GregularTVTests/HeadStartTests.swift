import Foundation
import GregularTVCore
import Testing
@testable import GregularTV

/// Tuning into a programme Jellyfin has to re-encode starts a little ahead of
/// live, so the transcode can get ahead before playback reaches it.
@MainActor @Suite(.serialized)
struct HeadStartTests {
    /// Answers PlaybackInfo with `reply`.
    struct Server: HTTPTransport {
        let reply: String

        func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            let body = request.url!.path.hasSuffix("/PlaybackInfo") ? Data(reply.utf8) : Data()
            return (body, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
    }

    nonisolated static let directPlay = #"{ "MediaSources": [{ "Id": "s", "SupportsDirectPlay": true }], "PlaySessionId": "p" }"#
    nonisolated static func hls(reasons: String) -> String {
        #"{ "MediaSources": [{ "Id": "s", "SupportsDirectPlay": false, "TranscodingUrl": "/videos/ep/master.m3u8?TranscodeReasons=\#(reasons)" }], "PlaySessionId": "p" }"#
    }

    /// A player ten minutes into an hour-long programme.
    private func player(reply: String) throws -> ChannelPlayer {
        let epoch = ISO8601DateFormatter().string(from: Date.now.addingTimeInterval(-600))
        let json = #"[{ "number": 1, "name": "C", "source": { "type": "all" }, "strategy": "derangement", "seed": 1, "epoch": "\#(epoch)" }]"#
        let items = [MediaItem(id: "ep", kind: .episode, name: "E", duration: 3600)]
        let schedule = try #require(try ChannelLineup.load(from: Data(json.utf8)).schedules(for: items).first)
        let client = JellyfinClient(
            credentials: Credentials(serverURL: URL(string: "https://tv.invalid")!, userID: "u", accessToken: "t"),
            identity: ClientIdentity(deviceID: "test"), transport: Server(reply: reply))
        return ChannelPlayer(schedule: schedule, client: client, quality: .hd10)
    }

    private func settledStatus(_ player: ChannelPlayer) async throws -> ChannelPlayer.Status {
        for _ in 0..<100 where player.status == .tuning { try await Task.sleep(for: .milliseconds(10)) }
        return player.status
    }

    @Test func aReencodedProgrammeStartsAheadOfLive() async throws {
        let player = try player(reply: Self.hls(reasons: "VideoCodecNotSupported"))
        player.tune()
        guard case .startingSoon(let at) = try await settledStatus(player) else {
            Issue.record("Expected a head start, not \(player.status)")
            return
        }
        #expect(abs(at.timeIntervalSinceNow - ChannelPlayer.transcodeHeadStart) < 2)
        player.stop()
    }

    @Test(arguments: [directPlay, hls(reasons: "ContainerNotSupported,AudioCodecNotSupported")])
    func aFileThatIsntReencodedStartsAtOnce(reply: String) async throws {
        let player = try player(reply: reply)
        player.tune()
        #expect(try await settledStatus(player) == .playing)
        player.stop()
    }

}
