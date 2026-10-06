import Foundation
import GregularCore

/// A signed-in connection to Jellyfin. Everything the app does with the
/// server after login goes through here.
///
/// **Privacy:** this type has no playback reporting (`/Sessions/Playing…`)
/// and never marks items as played. It registers no capabilities either, and
/// never opens the live connection Jellyfin sends remote control over, so
/// other Jellyfin apps can't control the TV. That's deliberate, and
/// `PrivacyTests` checks it. See PLAN.md §3.
public struct JellyfinClient: Sendable {
    public let credentials: Credentials
    /// What this device can play, for Jellyfin to choose between the file as it is and a conversion.
    public let formats: PlayableFormats
    private let api: JellyfinAPI

    public init(credentials: Credentials, identity: ClientIdentity, formats: PlayableFormats, transport: any HTTPTransport) {
        self.credentials = credentials
        self.formats = formats
        api = JellyfinAPI(server: credentials.serverURL, identity: identity,
                          token: credentials.accessToken, transport: transport)
    }

    /// Every playable episode and movie, held in memory by the caller.
    public func fetchLibrary() async throws -> [MediaItem] {
        try await LibraryQuery(api: api, userID: credentials.userID).fetchAll()
    }

    /// The items of `kinds` in the library called `name` (case-insensitive),
    /// for example the commercials. Nil if there's no library by that name.
    public func fetchLibrary(named name: String, kinds: Set<MediaItem.Kind>) async throws -> [MediaItem]? {
        let views: ItemsPage = try await api.get("/UserViews", query: [URLQueryItem(name: "userId", value: credentials.userID)])
        guard let library = views.items.first(where: { $0.name?.caseInsensitiveCompare(name) == .orderedSame }) else {
            return nil
        }
        return try await LibraryQuery(api: api, userID: credentials.userID).fetchAll(inLibrary: library.id, kinds: kinds)
    }

    /// A song's lyrics, if the server has them timed (Jellyfin 10.9 and
    /// later; the words' own timings from 10.10). Nil if it has none, or only
    /// untimed words.
    public func syncedLyrics(for itemID: String) async throws -> SyncedLyrics? {
        let lyrics: LyricsDTO
        do {
            lyrics = try await api.get("/Audio/\(itemID)/Lyrics")
        } catch JellyfinError.httpStatus(404) {
            return nil
        }
        return lyrics.synced
    }

    /// Where `item`'s original file is, to fetch whole, if this device plays
    /// it as it is. Nil if Jellyfin would have to convert it.
    ///
    /// Asked as if the server were on https even when it isn't: the file is
    /// fetched by the app itself, not by a web page's player, so a browser's
    /// rule against playing files from plain http doesn't apply (`PlayableFormats.playsFilesOnlyOverHTTPS`).
    public func originalFileURL(of item: MediaItem) async throws -> URL? {
        let info: PlaybackInfoResponse = try await api.post(
            "/Items/\(item.id)/PlaybackInfo",
            query: [
                URLQueryItem(name: "userId", value: credentials.userID),
                URLQueryItem(name: "mediaSourceId", value: item.id),
                URLQueryItem(name: "subtitleStreamIndex", value: "-1"),
            ],
            body: PlaybackInfoRequest(itemID: item.id, userId: credentials.userID, formats: formats,
                                      maxBitrate: StreamingQuality.maximumBitrate, secure: true))
        guard let source = info.mediaSources.first, source.supportsDirectPlay else { return nil }
        return directPlayURL(itemID: item.id, source: source, playSessionID: nil, isSong: item.kind == .song)
    }

    /// Asks Jellyfin how to play an item on this device, and returns the URL.
    /// - Parameter maxBitrate: the quality cap in bits per second (see `StreamingQuality`).
    public func playbackSource(
        for itemID: String, maxBitrate: Int = StreamingQuality.maximumBitrate
    ) async throws -> PlaybackSource {
        let info: PlaybackInfoResponse = try await api.post(
            "/Items/\(itemID)/PlaybackInfo",
            query: [
                URLQueryItem(name: "userId", value: credentials.userID),
                URLQueryItem(name: "maxStreamingBitrate", value: String(maxBitrate)),
                URLQueryItem(name: "mediaSourceId", value: itemID),
                URLQueryItem(name: "subtitleStreamIndex", value: "-1"),
            ],
            body: PlaybackInfoRequest(itemID: itemID, userId: credentials.userID, formats: formats, maxBitrate: maxBitrate,
                                      secure: credentials.serverURL.scheme?.lowercased() == "https"))

        guard let source = info.mediaSources.first else { throw JellyfinError.noPlayableSource(itemID: itemID) }

        if source.supportsDirectPlay {
            return PlaybackSource(url: directPlayURL(itemID: itemID, source: source, playSessionID: info.playSessionId, isSong: false),
                                  method: .directPlay, playSessionID: info.playSessionId)
        }
        if let transcodingURL = source.transcodingUrl, let url = serverRelativeURL(transcodingURL) {
            return PlaybackSource(url: url, method: .hls, playSessionID: info.playSessionId)
        }
        throw JellyfinError.noPlayableSource(itemID: itemID)
    }

    /// The fastest a measurement reports: 2 Gbps, far beyond any stream.
    static let fastestMeasured = 2_000_000_000

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
        // Capped: a server on the same machine can measure faster than a
        // 32-bit Int holds (WebAssembly's), far beyond any stream's need.
        return Int(min(Double(bytes * 8) / seconds, Double(Self.fastestMeasured)))
    }

    /// Stops the server's transcode for a play session. Call it when changing
    /// channel or when a programme ends.
    public func stopTranscoding(playSessionID: String) async throws {
        try await api.call("DELETE", "/Videos/ActiveEncodings", query: [
            URLQueryItem(name: "deviceId", value: api.identity.deviceID),
            URLQueryItem(name: "playSessionId", value: playSessionID),
        ])
    }

    /// Cancels the token on the server. False if the server couldn't be
    /// reached, or refused: then the token may still work there.
    @discardableResult
    public func revoke() async -> Bool {
        (try? await api.call("POST", "/Sessions/Logout")) != nil
    }

    /// Revokes the token on the server, then deletes this sign-in from
    /// `store` (any other servers' stay). The local copy is deleted even if
    /// the server can't be reached. Returns whether the server revoked it.
    @discardableResult
    public func signOut(clearing store: any CredentialStore) async -> Bool {
        let revoked = await revoke()
        try? store.deleteCredentials(credentials)
        return revoked
    }

    // MARK: - URLs

    /// AVPlayer can't attach an Authorization header to every request, so
    /// stream URLs carry the token as `ApiKey`, as all Jellyfin clients do.
    /// Jellyfin's own `TranscodingUrl` already includes it.
    /// - Parameter isSong: a sound file, which Jellyfin serves from `/Audio`.
    private func directPlayURL(itemID: String, source: PlaybackInfoResponse.MediaSource, playSessionID: String?, isSong: Bool) -> URL {
        let container = source.container?.split(separator: ",").first.map(String.init)
        var query = [
            URLQueryItem(name: "Static", value: "true"),
            URLQueryItem(name: "MediaSourceId", value: source.id),
            URLQueryItem(name: "DeviceId", value: api.identity.deviceID),
            URLQueryItem(name: "ApiKey", value: credentials.accessToken),
        ]
        if let playSessionID { query.append(URLQueryItem(name: "PlaySessionId", value: playSessionID)) }
        return api.url((isSong ? "/Audio/" : "/Videos/") + "\(itemID)/stream" + (container.map { ".\($0)" } ?? ""), query: query)
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

    public func fetchCollection(named name: String, kinds: Set<MediaItem.Kind>) async throws -> [MediaItem]? {
        try await fetchLibrary(named: name, kinds: kinds)
    }
}

extension JellyfinClient: LyricsSource {
    public func lyrics(for itemID: String) async throws -> SyncedLyrics? {
        try await syncedLyrics(for: itemID)
    }
}

extension JellyfinClient: OriginalFiles {
    public func originalFile(of item: MediaItem) async throws -> URL? {
        try await originalFileURL(of: item)
    }

    /// Only from this server, through its transport and rules.
    public func download(_ url: URL, mostBytes: Int) async throws -> Data {
        try await api.file(url, largest: mostBytes)
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

