import Foundation
import GregularCore
import Testing
@testable import GregularJellyfin

/// Finding the commercials library by name, and loading its videos.
struct CommercialsLibraryTests {
    let mock = MockJellyfin()

    @Test func findsTheLibraryByNameAndLoadsItsVideos() async throws {
        mock.on("GET", "/UserViews", json: #"{ "Items": [{ "Id": "v1", "Name": "Movies", "Type": "CollectionFolder" }, { "Id": "v2", "Name": "commercials", "Type": "CollectionFolder" }], "TotalRecordCount": 2 }"#)
        mock.on("GET", "/Items") { request in
            #expect(request.queryValue("ParentId") == "v2")
            #expect(request.queryValue("IncludeItemTypes")?.contains("Video") == true)
            return (200, #"{ "Items": [{ "Id": "a1", "Name": "Soda 1978", "Type": "Video", "RunTimeTicks": 300000000 }], "TotalRecordCount": 1 }"#)
        }
        let clips = try #require(try await JellyfinFixtures.client(mock).fetchLibrary(named: "Commercials"))
        #expect(clips.map(\.id) == ["a1"])
        #expect(clips[0].kind == .video && clips[0].duration == 30)
    }

    @Test func aMissingLibraryIsNil() async throws {
        mock.on("GET", "/UserViews", json: #"{ "Items": [{ "Id": "v1", "Name": "Movies", "Type": "CollectionFolder" }], "TotalRecordCount": 1 }"#)
        #expect(try await JellyfinFixtures.client(mock).fetchLibrary(named: "Commercials") == nil)
    }
}
