import Testing
@testable import GregularCore

/// What each device plays as it is.
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

    /// No browser reliably decodes 10-bit H.264, so the server converts it
    /// rather than sending a file the browser fails on. HEVC has limits only
    /// where the browser plays HEVC at all.
    @Test func browsersHearWhichH264TheyPlay() {
        for playsHEVC in [false, true] {
            let limits = PlayableFormats.browser(playsHEVC: playsHEVC).codecLimits
            let h264 = limits.first { $0.codec == "h264" }
            #expect(h264 == .eightBitH264 && h264?.profiles?.contains("high 10") == false)
            #expect(limits.contains { $0.codec == "hevc" } == playsHEVC)
        }
        #expect(PlayableFormats.appleTV.codecLimits.contains(.eightBitH264), "The same limit as Apple TV")
    }
}
