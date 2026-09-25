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
                Issue.record("Unexpected query \(request.url!)")
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

    @Test func parsesJellyfinDates() {
        #expect(ItemDTO.parseDate("2008-09-22T00:00:00.0000000Z") == Date(timeIntervalSince1970: 1_222_041_600))
        #expect(ItemDTO.parseDate("2008-09-22T13:30:15Z") == Date(timeIntervalSince1970: 1_222_090_215))
        #expect(ItemDTO.parseDate("garbage") == nil)
    }

    @Test func expiredTokenIsUnauthorized() async {
        mock.on("GET", "/Items", status: 401)
        await #expect(throws: JellyfinError.unauthorized) { try await JellyfinFixtures.client(mock).fetchLibrary() }
    }
}

struct JellyfinPlaybackTests {
    let mock = MockJellyfin()

    @Test func directPlayWhenSupported() async throws {
        mock.on("POST", "/Items/abc/PlaybackInfo") { request in
            #expect(request.jsonBody["DeviceProfile"] != nil)
            #expect(request.jsonBody["UserId"] as? String == "user-1")
            // No subtitles, so Jellyfin never burns them in (forcing a transcode).
            #expect(request.jsonBody["SubtitleStreamIndex"] as? Int == -1)
            #expect(request.queryValue("subtitleStreamIndex") == "-1")
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

    @Test func noSourcesIsAnError() async {
        mock.on("POST", "/Items/abc/PlaybackInfo", json: #"{ "MediaSources": [] }"#)
        await #expect(throws: JellyfinError.noPlayableSource(itemID: "abc")) {
            try await JellyfinFixtures.client(mock).playbackSource(for: "abc")
        }
    }

    @Test func stopTranscodingTargetsThisDeviceAndSession() async throws {
        mock.on("DELETE", "/Videos/ActiveEncodings", status: 204)
        try await JellyfinFixtures.client(mock).stopTranscoding(playSessionID: "ps1")
        let request = try #require(mock.requests.first)
        #expect(request.queryValue("deviceId") == "device-123")
        #expect(request.queryValue("playSessionId") == "ps1")
    }
}
