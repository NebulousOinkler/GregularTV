import Foundation
import Testing
import GregularCore
@testable import GregularJellyfin

struct JellyfinLibraryTests {
    let mock = MockJellyfin()

    private func page(_ items: [String], total: Int) -> String {
        #"{ "Items": [\#(items.joined(separator: ","))], "TotalRecordCount": \#(total), "StartIndex": 0 }"#
    }

    private func episode(_ id: String, season: Int, number: Int) -> String {
        #"{ "Id": "\#(id)", "Name": "Ep \#(number)", "Type": "Episode", "RunTimeTicks": 13200000000, "SeriesId": "s1", "SeriesName": "Alpha", "ParentIndexNumber": \#(season), "IndexNumber": \#(number) }"#
    }

    @Test func fetchesAllPagesAndInheritsSeriesGenres() async throws {
        mock.on("GET", "/Items") { request in
            #expect(request.queryValue("userId") == "user-1")
            #expect(request.queryValue("IsMissing") == "false")
            #expect(request.queryValue("EnableUserData") == "false")
            #expect(request.queryValue("Fields") == "Genres,Tags")

            switch (request.queryValue("IncludeItemTypes"), request.queryValue("StartIndex")) {
            case ("Series", _):
                return (200, self.page([#"{ "Id": "s1", "Name": "Alpha", "Type": "Series", "Genres": ["Comedy"], "Tags": ["Fav"], "ProductionYear": 2001 }"#], total: 1))
            case ("Episode,Movie", "0"):
                return (200, self.page([self.episode("e1", season: 1, number: 1), self.episode("e2", season: 1, number: 2)], total: 4))
            case ("Episode,Movie", "2"):
                return (200, self.page([
                    #"{ "Id": "m1", "Name": "Film", "Type": "Movie", "RunTimeTicks": 60000000000, "ProductionYear": 1999, "Genres": ["Drama"] }"#,
                    #"{ "Id": "m2", "Name": "No runtime", "Type": "Movie" }"#,
                ], total: 4))
            default:
                Issue.record("Unexpected query \(request.url)")
                return (500, "")
            }
        }

        let items = try await JellyfinFixtures.client(mock).fetchLibrary()

        #expect(items.map(\.id) == ["e1", "e2", "m1"])
        let e1 = items[0]
        #expect(e1.kind == .episode)
        #expect(e1.duration == 22 * 60)
        #expect(e1.seriesName == "Alpha" && e1.seasonNumber == 1 && e1.episodeNumber == 1)
        #expect(e1.genres == ["Comedy"])
        #expect(e1.tags == ["Fav"])
        #expect(e1.productionYear == 2001)
        #expect(items[2].genres == ["Drama"] && items[2].productionYear == 1999)
    }

    /// A library several pages long, served the way Jellyfin pages it
    /// (`StartIndex`, `Limit`), with the pages fetched in parallel: every
    /// episode and movie comes back exactly once, in the server's order.
    @Test func aLibraryOfManyPagesComesBackWhole() async throws {
        let episodes = (0..<2_345).map { self.episode(String(format: "e%05d", $0), season: 1, number: $0) }
        let movies = (0..<678).map { #"{ "Id": "m\#(String(format: "%05d", $0))", "Name": "Film", "Type": "Movie", "RunTimeTicks": 60000000000 }"# }
        let library = episodes + movies
        mock.on("GET", "/Items") { request in
            guard request.queryValue("IncludeItemTypes") == "Episode,Movie" else { return (200, self.page([], total: 0)) }
            let start = Int(request.queryValue("StartIndex")!)!, limit = Int(request.queryValue("Limit")!)!
            return (200, self.page(Array(library.dropFirst(start).prefix(limit)), total: library.count))
        }
        let items = try await JellyfinFixtures.client(mock).fetchLibrary()
        let expected = (0..<2_345).map { String(format: "e%05d", $0) } + (0..<678).map { String(format: "m%05d", $0) }
        #expect(items.map(\.id) == expected)
    }

    @Test func aFalseTotalFromTheServerIsNotBelieved() async throws {
        // A hostile server claims the most items there could be, then sends none.
        mock.on("GET", "/Items") { request in
            switch (request.queryValue("IncludeItemTypes"), request.queryValue("StartIndex")) {
            case ("Episode,Movie", "0"):
                return (200, self.page([self.episode("e1", season: 1, number: 1)], total: Int.max))
            case ("Episode,Movie", _):
                return (200, self.page([], total: Int.max))
            default:
                return (200, self.page([], total: 0))
            }
        }
        let items = try await JellyfinFixtures.client(mock).fetchLibrary()
        #expect(items.map(\.id) == ["e1"])
        let pageRequests = mock.requests.filter { $0.queryValue("IncludeItemTypes") == "Episode,Movie" }.count
        #expect(pageRequests <= 1 + 2 * LibraryQuery.maxConcurrentPages, "Stops once a page comes back empty")
    }

    @Test func aPageIsNeverMoreThanAPage() async throws {
        // A server that ignores the page size can't grow the library past what was asked for.
        let oversized = (0..<(LibraryQuery.pageSize + 50)).map { self.episode("e\($0)", season: 1, number: $0) }
        mock.on("GET", "/Items") { request in
            request.queryValue("IncludeItemTypes") == "Episode,Movie"
                ? (200, self.page(oversized, total: oversized.count)) : (200, self.page([], total: 0))
        }
        let items = try await JellyfinFixtures.client(mock).fetchLibrary()
        #expect(items.count <= 2 * LibraryQuery.pageSize)
    }

    @Test func parsesJellyfinDates() {
        #expect(ItemDTO.parseDate("2008-09-22T00:00:00.0000000Z") == Date(timeIntervalSince1970: 1_222_041_600))
        #expect(ItemDTO.parseDate("2008-09-22T13:30:15Z") == Date(timeIntervalSince1970: 1_222_090_215))
        #expect(ItemDTO.parseDate("garbage") == nil)
    }

    @Test func expiredTokenIsUnauthorized() async {
        mock.on("GET", "/Items", status: 401)
        await #expect(throws: JellyfinError.unauthorized) { try await JellyfinFixtures.client(mock).fetchLibrary() }
    }

    /// Only a 401 means the sign-in is gone: a 403 (a proxy's block, a
    /// programme the account may not watch) leaves it saved.
    @Test func aRefusalIsNotASignOut() async {
        mock.on("GET", "/Items", status: 403)
        await #expect(throws: JellyfinError.forbidden) { try await JellyfinFixtures.client(mock).fetchLibrary() }
        #expect(!JellyfinError.forbidden.isSessionExpired && JellyfinError.unauthorized.isSessionExpired)
    }

    /// A server sending pages of huge names is stopped before it fills memory.
    @Test func aLibraryOfHugeNamesIsStopped() async {
        let name = String(repeating: "x", count: 1_000_000)
        let items = (0..<100).map { #"{ "Id": "i\#($0)", "Name": "\#(name)", "Type": "Movie", "RunTimeTicks": 1 }"# }
        mock.on("GET", "/Items", json: #"{ "Items": [\#(items.joined(separator: ","))], "TotalRecordCount": 100000 }"#)
        await #expect(throws: JellyfinError.responseTooLarge) { try await JellyfinFixtures.client(mock).fetchLibrary() }
    }
}

struct JellyfinPlaybackTests {
    let mock = MockJellyfin()

    @Test func directPlayWhenSupported() async throws {
        mock.on("POST", "/Items/abc/PlaybackInfo") { request in
            #expect(request.jsonBody["DeviceProfile"] != nil)
            #expect(request.jsonBody["UserId"] as? String == "user-1")
            // No subtitles, so Jellyfin never burns them in (forcing a transcode).
            // It only honours that for a request naming its media source.
            #expect(request.jsonBody["SubtitleStreamIndex"] as? Int == -1)
            #expect(request.queryValue("subtitleStreamIndex") == "-1")
            #expect(request.jsonBody["MediaSourceId"] as? String == "abc")
            #expect(request.queryValue("mediaSourceId") == "abc")
            return (200, #"{ "MediaSources": [{ "Id": "src1", "Container": "mp4,m4v", "SupportsDirectPlay": true }], "PlaySessionId": "ps1" }"#)
        }
        let source = try await JellyfinFixtures.client(mock).playbackSource(for: "abc")

        #expect(source.method == .directPlay)
        #expect(source.playSessionID == "ps1")
        let components = try #require(URLComponents(url: source.url, resolvingAgainstBaseURL: false))
        #expect(components.path == "/Videos/abc/stream.mp4")
        let query = Dictionary(uniqueKeysWithValues: components.queryItems!.map { ($0.name, $0.value!) })
        #expect(query == ["Static": "true", "MediaSourceId": "src1", "DeviceId": "device-123",
                          "ApiKey": "token-abc", "PlaySessionId": "ps1"])
    }

    @Test func qualityCapIsSentToJellyfin() async throws {
        mock.on("POST", "/Items/abc/PlaybackInfo") { request in
            #expect(request.queryValue("maxStreamingBitrate") == "4000000")
            #expect(request.jsonBody["MaxStreamingBitrate"] as? Int == 4_000_000)
            let profile = request.jsonBody["DeviceProfile"] as? [String: Any]
            #expect(profile?["MaxStreamingBitrate"] as? Int == 4_000_000)
            // Subtitles are all "External", so Jellyfin never burns them in (a full transcode).
            let subtitles = profile?["SubtitleProfiles"] as? [[String: String]] ?? []
            #expect(subtitles.contains { $0["Format"] == "pgssub" && $0["Method"] == "External" })
            #expect(subtitles.allSatisfy { $0["Method"] == "External" })
            #expect(profile?["MaxStaticBitrate"] as? Int == 4_000_000)
            // A re-encode makes H.264, far less work than HEVC for a small server.
            let transcoding = profile?["TranscodingProfiles"] as? [[String: Any]] ?? []
            #expect(transcoding.first?["VideoCodec"] as? String == "h264,hevc")
            return (200, #"{ "MediaSources": [{ "Id": "s", "SupportsDirectPlay": true }] }"#)
        }
        _ = try await JellyfinFixtures.client(mock).playbackSource(for: "abc", maxBitrate: 4_000_000)
    }

    @Test func bandwidthTestWarmsUpThenTimesRequestedSize() async throws {
        mock.on("GET", "/Playback/BitrateTest") { request in
            (200, String(repeating: "x", count: Int(request.queryValue("size")!)!))
        }
        #expect(try await JellyfinFixtures.client(mock).measureBandwidth(bytes: 1000) > 0)
        #expect(mock.requests.map { $0.queryValue("size") } == ["64000", "1000"])
    }

    /// A server on the same machine answers faster than a 32-bit Int
    /// (WebAssembly's) can count: the measurement is capped, not a crash.
    @Test func aBlindinglyFastServerIsCappedNotOverflowing() async throws {
        mock.on("GET", "/Playback/BitrateTest") { request in
            (200, String(repeating: "x", count: Int(request.queryValue("size")!)!))
        }
        let measured = try await JellyfinFixtures.client(mock).measureBandwidth(bytes: 3_000_000)
        #expect(measured > 0 && measured <= JellyfinClient.fastestMeasured)
    }

    /// A browser plays H.264 and AAC in MP4, and from a plain http server
    /// nothing as a file at all: an https page can't load one (mixed content).
    @Test(arguments: [("https://tv.example", true), ("http://tv.local:8096", false)])
    func aBrowserAsksForWhatItCanPlay(server: String, playsFiles: Bool) async throws {
        mock.on("POST", "/Items/abc/PlaybackInfo") { request in
            let profile = request.jsonBody["DeviceProfile"] as? [String: Any]
            let direct = profile?["DirectPlayProfiles"] as? [[String: Any]] ?? []
            #expect(direct.isEmpty == !playsFiles)
            if playsFiles {
                #expect(direct.first?["VideoCodec"] as? String == "h264")
                #expect(direct.first?["AudioCodec"] as? String == "aac,mp3")
            }
            let transcoding = profile?["TranscodingProfiles"] as? [[String: Any]]
            #expect(transcoding?.first?["VideoCodec"] as? String == "h264")
            #expect(transcoding?.first?["AudioCodec"] as? String == "aac")
            #expect(transcoding?.first?["MaxAudioChannels"] as? String == "2")
            return (200, #"{ "MediaSources": [{ "Id": "s", "SupportsDirectPlay": true }] }"#)
        }
        let client = JellyfinClient(credentials: Credentials(serverURL: URL(string: server)!, userID: "user-1", accessToken: "t",
                                                             deviceID: "d"),
                                    identity: JellyfinFixtures.identity, formats: .browser(playsHEVC: false), transport: mock)
        _ = try await client.playbackSource(for: "abc")
    }

    @Test func hlsUsesTranscodingURLUnderReverseProxyPath() async throws {
        mock.on("POST", "/Items/abc/PlaybackInfo", json: """
            { "MediaSources": [{ "Id": "src1", "Container": "mkv", "SupportsDirectPlay": false,
              "TranscodingUrl": "/videos/abc/master.m3u8?MediaSourceId=src1&ApiKey=token-abc&VideoCodec=hevc,h264" }],
              "PlaySessionId": "ps2" }
            """)
        let proxied = URL(string: "https://media.example.com/jellyfin")!
        let source = try await JellyfinFixtures.client(mock, server: proxied).playbackSource(for: "abc")

        #expect(source.method == .hls)
        #expect(source.url.absoluteString
                == "https://media.example.com/jellyfin/videos/abc/master.m3u8?MediaSourceId=src1&ApiKey=token-abc&VideoCodec=hevc,h264")
    }

    /// Jellyfin's reasons reach the player in plain words; only a video
    /// reason means a re-encode.
    @Test func conversionReasonsArePlainWords() throws {
        let url = try #require(URL(string: "https://tv.invalid/master.m3u8?TranscodeReasons=ContainerNotSupported,AudioCodecNotSupported"))
        let stream = PlaybackSource(url: url, method: .hls, playSessionID: "p").mediaStream
        #expect(stream.conversionReasons == ["container not supported", "audio codec not supported"])
        #expect(!stream.reencodes && stream.delivery == .converted && stream.sessionID == "p")
    }

    @Test func noSourcesIsAnError() async {
        mock.on("POST", "/Items/abc/PlaybackInfo", json: #"{ "MediaSources": [] }"#)
        await #expect(throws: JellyfinError.noPlayableSource(itemID: "abc")) {
            try await JellyfinFixtures.client(mock).playbackSource(for: "abc")
        }
    }

    /// Apple TV's own player is fussy about H.264 and HEVC beyond their
    /// names: Jellyfin hears which profiles and tags it plays.
    @Test func appleTVSaysWhatItsPlayerIsFussyAbout() async throws {
        mock.on("POST", "/Items/abc/PlaybackInfo") { request in
            let profile = request.jsonBody["DeviceProfile"] as? [String: Any]
            let codecs = profile?["CodecProfiles"] as? [[String: Any]] ?? []
            let conditions = Dictionary(uniqueKeysWithValues: codecs.map { codec in
                (codec["Codec"] as! String, (codec["Conditions"] as! [[String: Any]]).map { "\($0["Property"]!)=\($0["Value"]!)" })
            })
            #expect(conditions["hevc"] == ["VideoProfile=main|main 10", "VideoCodecTag=hvc1|dvh1"])
            let h264 = try #require(conditions["h264"]?.first)
            #expect(h264.hasPrefix("VideoProfile=high|main|") && !h264.contains("high 10"))
            #expect(codecs.allSatisfy { $0["Type"] as? String == "Video" })
            let all = codecs.flatMap { $0["Conditions"] as! [[String: Any]] }
            #expect(all.allSatisfy { $0["Condition"] as? String == "EqualsAny" && $0["IsRequired"] as? Bool == false })
            return (200, #"{ "MediaSources": [{ "Id": "s", "SupportsDirectPlay": true }] }"#)
        }
        _ = try await JellyfinFixtures.client(mock).playbackSource(for: "abc")
    }

    /// VLC is asked about first, and plays every file it can as it is, even
    /// one Apple TV's own player plays too: the server only sends the file,
    /// and Apple TV's own player isn't asked about.
    @Test func vlcPlaysWhatItCanAsItIs() async throws {
        mock.on("POST", "/Items/abc/PlaybackInfo") { request in
            let profile = request.jsonBody["DeviceProfile"] as? [String: Any]
            #expect((profile?["Name"] as? String)?.contains("VLC") == true, "VLC first")
            // The common containers and codecs, not the rarest.
            let direct = profile?["DirectPlayProfiles"] as? [[String: Any]] ?? []
            let containers = (direct.first?["Container"] as? String)?.split(separator: ",") ?? []
            #expect(direct.count == 1 && containers.contains("mkv") && containers.contains("mp4") && !containers.contains("rm"))
            #expect((direct.first?["AudioCodec"] as? String)?.contains("dts") == true)
            #expect((direct.first?["VideoCodec"] as? String)?.contains("h261") == false)
            // Standard range only, whatever the codec: HDR is left to Apple TV's own player.
            let codecs = profile?["CodecProfiles"] as? [[String: Any]] ?? []
            #expect(codecs.count == 1 && codecs[0]["Codec"] == nil && codecs[0]["Type"] as? String == "Video")
            let condition = (codecs.first?["Conditions"] as? [[String: Any]])?.first
            #expect(condition?["Property"] as? String == "VideoRangeType" && condition?["Value"] as? String == "SDR")
            return (200, #"{ "MediaSources": [{ "Id": "src1", "Container": "mp4", "SupportsDirectPlay": true }], "PlaySessionId": "vlc" }"#)
        }
        let source = try await JellyfinFixtures.client(mock, addOn: .vlcOnAppleTV).playbackSource(for: "abc")

        #expect(source.player == .addOn && source.method == .directPlay)
        #expect(source.url.path == "/Videos/abc/stream.mp4")
        #expect(source.playSessionID == "vlc")
        #expect(source.mediaStream.player == .addOn && source.mediaStream.delivery == .original)
        #expect(source.mediaStream.sessionID == nil, "Nothing for the server to stop or keep going")
        #expect(mock.requests.count == 1, "Apple TV's own player isn't asked about")
    }

    /// An ID from the server goes into a path as one part of it, whatever it holds.
    @Test func anOddItemIDStaysInItsPlace() async throws {
        mock.on("POST", "/PlaybackInfo", json: #"{ "MediaSources": [{ "Id": "src1", "Container": "mp4/../x", "SupportsDirectPlay": true }] }"#)
        let source = try await JellyfinFixtures.client(mock).playbackSource(for: "../Users/me?x#y")
        let asked = try #require(mock.requests.first?.url.absoluteString)
        #expect(asked.hasPrefix("http://tv.local:8096/Items/%2E%2E%2FUsers%2Fme%3Fx%23y/PlaybackInfo?"))
        #expect(source.url.absoluteString.hasPrefix("http://tv.local:8096/Videos/%2E%2E%2FUsers%2Fme%3Fx%23y/stream.mp4%2F%2E%2E%2Fx?"))
    }

    /// What VLC can't play as it is (HDR, or over the quality cap, say)
    /// goes to Apple TV's own player: as it is if it can, otherwise converted
    /// by the server.
    @Test func otherwiseTheOwnPlayerHasIt() async throws {
        let vlcSaysNo = #"{ "MediaSources": [{ "Id": "x", "SupportsDirectPlay": false, "TranscodingUrl": "/videos/x/main.m3u8" }] }"#
        let isVLC = { (request: ServerRequest) in
            ((request.jsonBody["DeviceProfile"] as? [String: Any])?["Name"] as? String)?.contains("VLC") == true
        }
        mock.on("POST", "/Items/abc/PlaybackInfo") { request in
            isVLC(request) ? (200, vlcSaysNo) : (200, """
                { "MediaSources": [{ "Id": "src1", "Container": "mkv", "SupportsDirectPlay": false,
                  "TranscodingUrl": "/videos/abc/master.m3u8?TranscodeReasons=ContainerBitrateExceedsLimit" }], "PlaySessionId": "ps" }
                """)
        }
        mock.on("POST", "/Items/hdr/PlaybackInfo") { request in
            isVLC(request) ? (200, vlcSaysNo) : (200, #"{ "MediaSources": [{ "Id": "hdr", "Container": "mp4", "SupportsDirectPlay": true }] }"#)
        }
        let client = JellyfinFixtures.client(mock, addOn: .vlcOnAppleTV)

        let converted = try await client.playbackSource(for: "abc")
        #expect(converted.player == .builtIn && converted.method == .hls && converted.playSessionID == "ps")
        #expect(mock.requests.count == 2, "Asked about each player")

        let direct = try await client.playbackSource(for: "hdr")
        #expect(direct.player == .builtIn && direct.method == .directPlay)
        #expect(mock.requests.count == 4)
    }

    /// Asked about Apple TV's own player first (a commercial), a file it
    /// plays as it is goes to it, and VLC isn't asked about; one it can't
    /// goes to VLC, if VLC plays it as it is.
    @Test func theOrderAskedForIsTheOrderTried() async throws {
        let answer = { (direct: Bool) in #"{ "MediaSources": [{ "Id": "s", "Container": "mkv", "SupportsDirectPlay": \#(direct) }] }"# }
        let isVLC = { (request: ServerRequest) in
            ((request.jsonBody["DeviceProfile"] as? [String: Any])?["Name"] as? String)?.contains("VLC") == true
        }
        mock.on("POST", "/Items/mp4/PlaybackInfo") { request in (200, answer(true)) }
        mock.on("POST", "/Items/mkv/PlaybackInfo") { request in (200, answer(isVLC(request))) }
        let client = JellyfinFixtures.client(mock, addOn: .vlcOnAppleTV)

        let own = try await client.playbackSource(for: "mp4", players: [.builtIn, .addOn])
        #expect(own.player == .builtIn && own.method == .directPlay && mock.requests.count == 1)

        let vlc = try await client.playbackSource(for: "mkv", players: [.builtIn, .addOn])
        #expect(vlc.player == .addOn && vlc.method == .directPlay && mock.requests.count == 3)
    }

    /// With only Apple TV's own player to ask about (VLC failed on it),
    /// VLC is left out.
    @Test func aPlayerNotAskedAboutIsLeftOut() async throws {
        mock.on("POST", "/Items/abc/PlaybackInfo") { request in
            let name = (request.jsonBody["DeviceProfile"] as? [String: Any])?["Name"] as? String
            #expect(name?.contains("VLC") == false)
            return (200, #"{ "MediaSources": [{ "Id": "src1", "Container": "mp4", "SupportsDirectPlay": true }] }"#)
        }
        let client = JellyfinFixtures.client(mock, addOn: .vlcOnAppleTV)
        let source = try await client.playbackSource(for: "abc", players: [.builtIn])
        #expect(source.player == .builtIn && source.method == .directPlay && mock.requests.count == 1)
        #expect(client.players == [.builtIn, .addOn] && JellyfinFixtures.client(mock).players == [.builtIn])
    }

    /// With only VLC to ask about (Apple TV's own player failed on a
    /// commercial), a file VLC can't play as it is is converted for Apple
    /// TV's own player all the same.
    @Test func whatNoPlayerAskedAboutPlaysIsConverted() async throws {
        mock.on("POST", "/Items/abc/PlaybackInfo", json: """
            { "MediaSources": [{ "Id": "src1", "Container": "avi", "SupportsDirectPlay": false,
              "TranscodingUrl": "/videos/abc/master.m3u8?x=1" }], "PlaySessionId": "ps" }
            """)
        let source = try await JellyfinFixtures.client(mock, addOn: .vlcOnAppleTV).playbackSource(for: "abc", players: [.addOn])
        #expect(source.player == .builtIn && source.method == .hls && mock.requests.count == 2)
    }

    @Test func stopTranscodingTargetsThisDeviceAndSession() async throws {
        mock.on("DELETE", "/Videos/ActiveEncodings", status: 204)
        try await JellyfinFixtures.client(mock).stopTranscoding(playSessionID: "ps1")
        let request = try #require(mock.requests.first)
        #expect(request.queryValue("deviceId") == "device-123")
        #expect(request.queryValue("playSessionId") == "ps1")
    }
}
