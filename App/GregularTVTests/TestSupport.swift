import Foundation
import GregularCore
import GregularJellyfin
@testable import GregularScreens
@testable import GregularTV

/// The app's tests play on real AVFoundation decks, as the app does.
extension ChannelPlayer {
    convenience init(schedule: ChannelSchedule, streams: any StreamSource, quality: StreamingQuality) {
        self.init(schedule: schedule, streams: streams, quality: quality, decks: AVPlayerDeck.pair())
    }
}

extension ChannelSurfer {
    convenience init(channels: [ChannelSchedule], startingWith channel: ChannelSchedule,
                     streams: any StreamSource, preferences: AppPreferences) {
        self.init(channels: channels, startingWith: channel, streams: streams, preferences: preferences,
                  decks: AVPlayerDeck.pair())
    }
}

extension JellyfinClient {
    /// A client for a server that doesn't exist, whose every reply comes from `transport`.
    static func testing(_ transport: any HTTPTransport) -> JellyfinClient {
        JellyfinClient(credentials: Credentials(serverURL: URL(string: "https://tv.invalid")!, userID: "u", accessToken: "t", deviceID: "d-t"),
                       identity: ClientIdentity(deviceID: "test", deviceName: "Apple TV"), formats: .appleTV, transport: transport)
    }
}

/// A pretend Jellyfin server for the player's tests. PlaybackInfo answers
/// with `reply`, a speed test with 1000 bytes after `speedTestDelay`, and
/// anything else with nothing. Every request is kept, to check what was asked.
final class FakeServer: HTTPTransport, @unchecked Sendable {
    /// PlaybackInfo for a file the Apple TV plays as it is.
    static let directPlay = #"{ "MediaSources": [{ "Id": "s", "SupportsDirectPlay": true }], "PlaySessionId": "p" }"#

    /// PlaybackInfo for a file Jellyfin would convert, for `reasons`.
    static func hls(reasons: String) -> String {
        #"{ "MediaSources": [{ "Id": "s", "SupportsDirectPlay": false, "TranscodingUrl": "/videos/s/master.m3u8?TranscodeReasons=\#(reasons)" }], "PlaySessionId": "p" }"#
    }

    let reply: String
    let speedTestDelay: Duration
    private let lock = NSLock()
    private var log: [ServerRequest] = []

    init(reply: String = directPlay, speedTestDelay: Duration = .zero) {
        self.reply = reply
        self.speedTestDelay = speedTestDelay
    }

    var requests: [ServerRequest] { lock.withLock { log } }
    var playbackInfos: [ServerRequest] { requests.filter { $0.url.path.hasSuffix("/PlaybackInfo") } }
    var speedTests: Int { requests.filter { $0.url.path.hasSuffix("/Playback/BitrateTest") }.count }
    /// The bitrate cap each PlaybackInfo asked for (0 if none), in order.
    var requestedCaps: [Int] {
        playbackInfos.map { request in
            URLComponents(url: request.url, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "maxStreamingBitrate" }?.value.flatMap { Int($0) } ?? 0
        }
    }

    func send(_ request: ServerRequest) async throws -> ServerReply {
        lock.withLock { log.append(request) }
        var body = Data()
        if request.url.path.hasSuffix("/Playback/BitrateTest") {
            try await Task.sleep(for: speedTestDelay)
            body = Data(count: 1000)
        } else if request.url.path.hasSuffix("/PlaybackInfo") {
            body = Data(reply.utf8)
        }
        return ServerReply(url: request.url, status: 200, body: body)
    }
}

/// A server that can't be reached.
struct OfflineTransport: HTTPTransport {
    func send(_ request: ServerRequest) async throws -> ServerReply {
        throw URLError(.notConnectedToInternet)
    }
}

/// A server that no longer accepts the sign-in.
struct RevokedTransport: HTTPTransport {
    func send(_ request: ServerRequest) async throws -> ServerReply {
        ServerReply(url: request.url, status: 401, body: Data())
    }
}
