import Foundation
import GregularCore

/// A signed-in connection to Jellyfin. Everything the app does with the
/// server after login goes through here.
///
/// **Privacy:** this type has no playback reporting (`/Sessions/Playing…`)
/// and never marks items as played. That's deliberate, and
/// `PrivacyTests` checks it. See PLAN.md §3.
public struct JellyfinClient: Sendable {
    public let credentials: Credentials
    private let api: JellyfinAPI

    public init(credentials: Credentials, identity: ClientIdentity, transport: any HTTPTransport = URLSessionTransport.shared) {
        self.credentials = credentials
        api = JellyfinAPI(server: credentials.serverURL, identity: identity,
                          token: credentials.accessToken, transport: transport)
    }

    /// Tells Jellyfin this device plays video but can't be remote-controlled,
    /// so other clients can't push commands to the TV.
    public func registerCapabilities() async throws {
        try await api.call("POST", "/Sessions/Capabilities/Full", body: Capabilities())
    }

    /// Every playable episode and movie, held in memory by the caller.
    public func fetchLibrary() async throws -> [MediaItem] {
        try await LibraryQuery(api: api, userID: credentials.userID).fetchAll()
    }

    /// The videos in the library called `name` (case-insensitive), for example
    /// the commercials. Nil if there's no library by that name.
    public func fetchLibrary(named name: String) async throws -> [MediaItem]? {
        let views: ItemsPage = try await api.get("/UserViews", query: [URLQueryItem(name: "userId", value: credentials.userID)])
        guard let library = views.items.first(where: { $0.name?.caseInsensitiveCompare(name) == .orderedSame }) else {
            return nil
        }
        return try await LibraryQuery(api: api, userID: credentials.userID).fetchAll(inLibrary: library.id)
    }

    /// Asks Jellyfin how to play an item on Apple TV, and returns the URL.
    /// - Parameter maxBitrate: the quality cap in bits per second (see `StreamingQuality`).
    public func playbackSource(
        for itemID: String, maxBitrate: Int = StreamingQuality.maximumBitrate
    ) async throws -> PlaybackSource {
        let info: PlaybackInfoResponse = try await api.post(
            "/Items/\(itemID)/PlaybackInfo",
            query: [
                URLQueryItem(name: "userId", value: credentials.userID),
                URLQueryItem(name: "maxStreamingBitrate", value: String(maxBitrate)),
                URLQueryItem(name: "subtitleStreamIndex", value: "-1"),
            ],
            body: PlaybackInfoRequest(userId: credentials.userID, maxBitrate: maxBitrate))

        guard let source = info.mediaSources.first else { throw JellyfinError.noPlayableSource(itemID: itemID) }

        if source.supportsDirectPlay {
            return PlaybackSource(url: directPlayURL(itemID: itemID, source: source, playSessionID: info.playSessionId),
                                  method: .directPlay, playSessionID: info.playSessionId)
        }
        if let transcodingURL = source.transcodingUrl, let url = serverRelativeURL(transcodingURL) {
            return PlaybackSource(url: url, method: .hls, playSessionID: info.playSessionId)
        }
        throw JellyfinError.noPlayableSource(itemID: itemID)
    }

    /// Measures how fast the server can send data right now, in bits per
    /// second, by downloading `bytes` of test data from Jellyfin's bitrate
    /// test endpoint. It reflects both the network and how busy the server is.
    public func measureBandwidth(bytes: Int) async throws -> Int {
        // Warm-up: the first request pays for DNS, TCP and the TLS handshake
        // (slow through a relay such as Tailscale Funnel). Timing it would make
        // the server look far slower than it streams. The timed request then
        // reuses the open connection.
        try await api.call("GET", "/Playback/BitrateTest", query: [URLQueryItem(name: "size", value: "64000")])
        let start = ContinuousClock.now
        try await api.call("GET", "/Playback/BitrateTest", query: [URLQueryItem(name: "size", value: String(bytes))])
        let seconds = max(0.001, (ContinuousClock.now - start) / .seconds(1))
        return Int(Double(bytes * 8) / seconds)
    }

    /// Stops the server's transcode for a play session. Call it when changing
    /// channel or when a programme ends.
    public func stopTranscoding(playSessionID: String) async throws {
        try await api.call("DELETE", "/Videos/ActiveEncodings", query: [
            URLQueryItem(name: "deviceId", value: api.identity.deviceID),
            URLQueryItem(name: "playSessionId", value: playSessionID),
        ])
    }

    /// Revokes the token on the server, then deletes the local credentials.
    /// The local copy is deleted even if the server can't be reached.
    public func signOut(clearing store: any CredentialStore) async {
        try? await api.call("POST", "/Sessions/Logout")
        try? store.deleteCredentials()
    }

    // MARK: - URLs

    /// AVPlayer can't attach an Authorization header to every request, so
    /// stream URLs carry the token as `ApiKey`, as all Jellyfin clients do.
    /// Jellyfin's own `TranscodingUrl` already includes it.
    private func directPlayURL(itemID: String, source: PlaybackInfoResponse.MediaSource, playSessionID: String?) -> URL {
        let container = source.container?.split(separator: ",").first.map(String.init)
        var query = [
            URLQueryItem(name: "Static", value: "true"),
            URLQueryItem(name: "MediaSourceId", value: source.id),
            URLQueryItem(name: "DeviceId", value: api.identity.deviceID),
            URLQueryItem(name: "ApiKey", value: credentials.accessToken),
        ]
        if let playSessionID { query.append(URLQueryItem(name: "PlaySessionId", value: playSessionID)) }
        return api.url("/Videos/\(itemID)/stream" + (container.map { ".\($0)" } ?? ""), query: query)
    }

    /// Jellyfin returns `TranscodingUrl` as a server-relative path. Prefix the
    /// server URL, including any reverse-proxy sub-path.
    private func serverRelativeURL(_ relative: String) -> URL? {
        guard let parsed = URLComponents(string: relative),
              var components = URLComponents(url: credentials.serverURL, resolvingAgainstBaseURL: false)
        else { return nil }
        components.path += parsed.path
        components.percentEncodedQuery = parsed.percentEncodedQuery
        return components.url
    }
}

// MARK: - As the schedule's media services

extension JellyfinClient: MediaLibrary {
    public func fetchProgrammes() async throws -> [MediaItem] {
        try await fetchLibrary()
    }

    public func fetchCollection(named name: String) async throws -> [MediaItem]? {
        try await fetchLibrary(named: name)
    }
}

extension JellyfinClient: StreamSource {
    public func stream(for itemID: String, maxBitrate: Int) async throws -> MediaStream {
        try await playbackSource(for: itemID, maxBitrate: maxBitrate).mediaStream
    }

    public func release(_ stream: MediaStream) async {
        guard let session = stream.sessionID else { return }
        try? await stopTranscoding(playSessionID: session)
    }

    public func measureBandwidth() async throws -> Int {
        try await measureBandwidth(bytes: 3_000_000)
    }
}

private struct Capabilities: Encodable {
    let playableMediaTypes = ["Video"]
    let supportedCommands: [String] = []
    let supportsMediaControl = false
}
