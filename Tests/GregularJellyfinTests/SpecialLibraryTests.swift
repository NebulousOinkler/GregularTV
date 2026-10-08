import Foundation
import GregularCore
import Testing
@testable import GregularJellyfin

/// What special modes read from Jellyfin: songs and music videos in a
/// library, their lyrics, and whether their original files play as they are.
struct SpecialLibraryTests {
    let mock = MockJellyfin()

    private func views(_ names: String...) {
        let items = names.enumerated().map { #"{ "Id": "v\#($0.offset)", "Name": "\#($0.element)", "Type": "CollectionFolder" }"# }
        mock.on("GET", "/UserViews", json: #"{ "Items": [\#(items.joined(separator: ","))], "TotalRecordCount": \#(names.count) }"#)
    }

    @Test func songsAndMusicVideosComeWithTheirArtistsAndAlbums() async throws {
        views("Karaoke")
        mock.on("GET", "/Items") { request in
            #expect(request.queryValue("IncludeItemTypes") == "Audio,MusicVideo")
            #expect(request.queryValue("Fields") == "Genres,Tags,ParentId")
            #expect(request.queryValue("EnableImages") == "false", "Never artwork")
            return (200, #"""
            { "Items": [
                { "Id": "s1", "Name": "Dancing Queen", "Type": "Audio", "RunTimeTicks": 2310000000, "Artists": ["ABBA"],
                  "Album": "Arrival", "HasLyrics": true, "Container": "mp3", "ParentId": "v0" },
                { "Id": "m1", "Name": "Waterloo", "Type": "MusicVideo", "RunTimeTicks": 1680000000, "Artists": ["ABBA"],
                  "Container": "mov,mp4,m4a,3gp,3g2,mj2", "ParentId": "v0" }
            ], "TotalRecordCount": 2 }
            """#)
        }
        let songs = try #require(try await JellyfinFixtures.client(mock).fetchLibrary(named: "karaoke", kinds: [.song, .musicVideo]))
        #expect(songs == [
            MediaItem(id: "s1", kind: .song, name: "Dancing Queen", duration: 231, artists: ["ABBA"], album: "Arrival",
                      hasLyrics: true, container: "mp3"),
            MediaItem(id: "m1", kind: .musicVideo, name: "Waterloo", duration: 168, artists: ["ABBA"],
                      container: "mov,mp4,m4a,3gp,3g2,mj2"),
        ])
        #expect(mock.requests.count == 2, "Nothing's in a folder, so the folders aren't fetched")
    }

    /// Libraries arranged by folder (Artist/Album/Title) say so through `folders`.
    @Test func itemsInFoldersAreToldTheirNames() async throws {
        views("Karaoke")
        mock.on("GET", "/Items") { request in
            if request.queryValue("IncludeItemTypes") == "Folder" {
                #expect(request.queryValue("ParentId") == "v0")
                return (200, #"""
                { "Items": [ { "Id": "f1", "Name": "ABBA", "Type": "Folder", "ParentId": "v0" },
                             { "Id": "f2", "Name": "Arrival", "Type": "Folder", "ParentId": "f1" } ], "TotalRecordCount": 2 }
                """#)
            }
            return (200, #"""
            { "Items": [ { "Id": "a", "Name": "Dancing Queen", "Type": "Video", "RunTimeTicks": 2310000000, "ParentId": "f2" },
                         { "Id": "b", "Name": "Loose", "Type": "Video", "RunTimeTicks": 1200000000, "ParentId": "v0" } ],
              "TotalRecordCount": 2 }
            """#)
        }
        let items = try #require(try await JellyfinFixtures.client(mock).fetchLibrary(named: "Karaoke", kinds: [.video]))
        #expect(items.map(\.folders) == [["ABBA", "Arrival"], []])
    }

    @Test func lyricsAreTimedByLineAndByWord() async throws {
        mock.on("GET", "/Audio/s1/Lyrics", json: #"""
        { "Metadata": {}, "Lyrics": [
            { "Text": "You can dance", "Start": 450000000,
              "Cues": [ { "Position": 0, "EndPosition": 3, "Start": 450000000, "End": 455000000 },
                        { "Position": 4, "EndPosition": 7, "Start": 455000000 },
                        { "Position": 8, "Start": 460000000 } ] },
            { "Text": "Having the time of your life", "Start": 400000000 }
        ] }
        """#)
        let lyrics = try #require(try await JellyfinFixtures.client(mock).lyrics(for: "s1"))
        #expect(lyrics.lines.map(\.start) == [40, 45], "In order of time")
        #expect(lyrics.lines[0].words.isEmpty, "Only the line is timed")
        #expect(lyrics.lines[1].words == [
            SyncedLyrics.Word(range: 0..<3, start: 45, end: 45.5),
            SyncedLyrics.Word(range: 4..<7, start: 45.5),
            SyncedLyrics.Word(range: 8..<13, start: 46),
        ])
    }

    /// .NET counts UTF-16 units; words are counted in characters.
    @Test func wordsAreCountedInCharacters() async throws {
        mock.on("GET", "/Audio/s1/Lyrics", json: #"""
        { "Lyrics": [ { "Text": "🎤 Sing", "Start": 0,
                        "Cues": [ { "Position": 0, "EndPosition": 2, "Start": 0 }, { "Position": 3, "EndPosition": 7, "Start": 10000000 } ] } ] }
        """#)
        let words = try #require(try await JellyfinFixtures.client(mock).lyrics(for: "s1")).lines[0].words
        #expect(words.map(\.range) == [0..<1, 2..<6])
    }

    @Test func untimedOrMissingLyricsAreNone() async throws {
        mock.on("GET", "/Audio/plain/Lyrics", json: #"{ "Lyrics": [ { "Text": "Just words" } ] }"#)
        let client = JellyfinFixtures.client(mock)
        #expect(try await client.lyrics(for: "plain") == nil)
        #expect(try await client.lyrics(for: "missing") == nil, "404: no lyrics")
    }

    @Test func aSongThatPlaysAsItIsHasItsOriginalFile() async throws {
        mock.on("POST", "/Items/s1/PlaybackInfo") { request in
            let profiles = (request.jsonBody["DeviceProfile"] as? [String: Any])?["DirectPlayProfiles"] as? [[String: Any]]
            #expect(profiles?.map { $0["Type"] as? String } == ["Video", "Audio"])
            return (200, #"{ "MediaSources": [{ "Id": "s1", "Container": "mp3", "SupportsDirectPlay": true }], "PlaySessionId": "p" }"#)
        }
        let song = MediaItem(id: "s1", kind: .song, name: "Dancing Queen", duration: 231)
        let url = try #require(try await JellyfinFixtures.client(mock).originalFile(of: song))
        #expect(url.path == "/Audio/s1/stream.mp3")
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(query.contains(URLQueryItem(name: "Static", value: "true")))
        #expect(query.contains(URLQueryItem(name: "ApiKey", value: "token-abc")))
    }

    @Test func oneThatWouldBeConvertedHasNone() async throws {
        mock.on("POST", "/Items/m1/PlaybackInfo",
                json: #"{ "MediaSources": [{ "Id": "m1", "SupportsDirectPlay": false, "TranscodingUrl": "/videos/m1/master.m3u8" }] }"#)
        let video = MediaItem(id: "m1", kind: .musicVideo, name: "Waterloo", duration: 168)
        #expect(try await JellyfinFixtures.client(mock).originalFile(of: video) == nil)
    }

    @Test func aWholeFileComesFromItsOwnServerOnly() async throws {
        mock.on("GET", "/Audio/s1/stream.mp3", json: String(repeating: "x", count: 2000))
        let client = JellyfinFixtures.client(mock)
        let song = URL(string: "http://tv.local:8096/Audio/s1/stream.mp3?Static=true")!
        #expect(try await client.download(song, mostBytes: 5000).count == 2000)
        await #expect(throws: JellyfinError.responseTooLarge) { try await client.download(song, mostBytes: 1000) }
        for elsewhere in ["http://other.local:8096/Audio/s1/stream.mp3", "https://tv.local:8096/Audio/s1/stream.mp3",
                          "http://tv.local:9000/Audio/s1/stream.mp3"] {
            await #expect(throws: JellyfinError.invalidResponse) { try await client.download(URL(string: elsewhere)!, mostBytes: 5000) }
            #expect(throws: JellyfinError.invalidResponse, "A browser fetching it itself checks the same") {
                try client.checkDownload(URL(string: elsewhere)!)
            }
        }
        try client.checkDownload(song)
        #expect(mock.requests.count == 2, "Nothing sent anywhere else")
    }

    /// A browser fetches the file itself, so plain http to the home network is fine for it.
    @Test func aBrowserAsksForTheOriginalEvenFromPlainHTTP() async throws {
        mock.on("POST", "/Items/m1/PlaybackInfo") { request in
            let profiles = (request.jsonBody["DeviceProfile"] as? [String: Any])?["DirectPlayProfiles"] as? [[String: Any]]
            #expect(profiles?.isEmpty == false)
            return (200, #"{ "MediaSources": [{ "Id": "m1", "Container": "mp4", "SupportsDirectPlay": true }] }"#)
        }
        let client = JellyfinClient(credentials: JellyfinFixtures.credentials, identity: JellyfinFixtures.identity,
                                    formats: .browser(playsHEVC: false), transport: mock)
        let video = MediaItem(id: "m1", kind: .musicVideo, name: "Waterloo", duration: 168)
        #expect(try await client.originalFile(of: video)?.path == "/Videos/m1/stream.mp4")
    }
}
