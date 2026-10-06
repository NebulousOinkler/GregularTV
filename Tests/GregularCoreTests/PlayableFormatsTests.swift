import Testing
@testable import GregularCore

/// Telling from a file's container whether it could play as it is.
struct PlayableFormatsTests {
    @Test func aContainerIsJudgedByItsKind() {
        let tv = PlayableFormats.appleTV
        #expect(tv.mightPlayAsIs(.song, container: "flac"))
        #expect(!tv.mightPlayAsIs(.song, container: "ogg"))
        #expect(tv.mightPlayAsIs(.musicVideo, container: "mov,mp4,m4a,3gp,3g2,mj2"), "Any of the names the server gives")
        #expect(!tv.mightPlayAsIs(.musicVideo, container: "mkv"))
        #expect(!tv.mightPlayAsIs(.video, container: "MKV"))
        #expect(tv.mightPlayAsIs(.video, container: nil), "Unknown: only the server can say")
    }
}
