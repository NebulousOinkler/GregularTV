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
        for alsoPlays in [[], [MediaFormat(.video, "hevc", profile: "main")]] as [Set<MediaFormat>] {
            let limits = PlayableFormats.browser(alsoPlays: alsoPlays).codecLimits
            let h264 = limits.first { $0.codec == "h264" }
            #expect(h264 == .eightBitH264 && h264?.profiles?.contains("high 10") == false)
            #expect(limits.contains { $0.codec == "hevc" } == !alsoPlays.isEmpty)
        }
        #expect(PlayableFormats.appleTV.codecLimits.contains(.eightBitH264), "The same limit as Apple TV")
    }

    /// Only what the browser confirms: HEVC by the profiles it says, and the
    /// sound formats it says, which copy into a conversion as they are.
    @Test func browsersDeclareOnlyWhatTheyConfirm() {
        let plain = PlayableFormats.browser(alsoPlays: [])
        #expect(plain.videoCodecs == ["h264"] && plain.audioCodecs == ["aac", "mp3"] && plain.mostAudioChannels == 2)
        let main = PlayableFormats.browser(alsoPlays: [MediaFormat(.video, "hevc", profile: "main")])
        #expect(main.codecLimits.first { $0.codec == "hevc" }?.profiles == ["main"], "Not Main 10 unless it says")
        let surround = PlayableFormats.browser(alsoPlays: [MediaFormat(.sound, "eac3"), MediaFormat(.video, "av1")])
        #expect(surround.audioCodecs.contains("eac3") && surround.convertedAudioCodecs == ["aac", "eac3"])
        #expect(surround.videoCodecs == ["h264", "av1"] && surround.mostAudioChannels == 6)
        #expect(surround.safestFormats == plain.safestFormats, "H.264 and AAC stay the safest")
    }

    @Test func vlcPlaysTrueHD() {
        #expect(PlayableFormats.vlcOnAppleTV.audioCodecs.contains("truehd"))
    }
}

/// Leaving out what a player turned out not to decode.
struct PlayableFormatsWithoutTests {
    @Test func aVideoProfileComesOffItsCodecsLimit() {
        let tv = PlayableFormats.appleTV.without([MediaFormat(.video, "hevc", profile: "Main 10")])
        let hevc = tv.codecLimits.first { $0.codec == "hevc" }
        #expect(hevc?.profiles == ["main"] && hevc?.tags == ["hvc1", "dvh1"] && tv.videoCodecs.contains("hevc"))
    }

    @Test func aCodecWithNoLimitGoesWhole() {
        let tv = PlayableFormats.appleTV.without([MediaFormat(.sound, "eac3"), MediaFormat(.video, "hevc")])
        #expect(!tv.audioCodecs.contains("eac3") && !tv.convertedAudioCodecs.contains("eac3"))
        #expect(!tv.videoCodecs.contains("hevc") && !tv.convertedVideoCodecs.contains("hevc"))
        #expect(!tv.codecLimits.contains { $0.codec == "hevc" })
        #expect(tv.safestFormats == [MediaFormat(.video, "h264"), MediaFormat(.sound, "aac")])
    }

    @Test func nothingToLeaveOutLeavesItAsItIs() {
        #expect(PlayableFormats.appleTV.without([]) == .appleTV)
    }
}
