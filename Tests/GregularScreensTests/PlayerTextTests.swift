import GregularCore
import Testing
@testable import GregularScreens

/// The player's words, for every deck alike.
struct PlayerTextTests {
    /// No cap says so, rather than naming the highest there is; a
    /// commercial says it is one, at its programme's cap.
    @Test func theStreamSaysWhatSetItsCap() {
        let max = StreamingQuality.maximumBitrate
        #expect(PlayerText.stream(quality: .auto, fixedForProgramme: false, isCommercial: false, cap: max, delivery: .original)
                == "Auto · no cap · direct play")
        #expect(PlayerText.stream(quality: .hd10, fixedForProgramme: false, isCommercial: false, cap: 10_000_000, delivery: .original)
                == "1080p · 10 Mbps · up to 10 Mbps · direct play")
        #expect(PlayerText.stream(quality: .auto, fixedForProgramme: false, isCommercial: false, cap: 7_000_000, delivery: .reencoded)
                == "Auto · up to 7 Mbps · re-encoded by the server")
        #expect(PlayerText.stream(quality: .hd10, fixedForProgramme: true, isCommercial: false, cap: 1_500_000, delivery: .soundConverted)
                == "This programme only · up to 1.5 Mbps · sound converted by the server")
        #expect(PlayerText.stream(quality: .hd720, fixedForProgramme: false, isCommercial: true, cap: 4_000_000, delivery: .reencoded)
                == "Commercial · 720p · 4 Mbps · up to 4 Mbps · re-encoded by the server")
        #expect(PlayerText.stream(quality: .auto, fixedForProgramme: false, isCommercial: true, cap: max, delivery: .original)
                == "Commercial · Auto · no cap · direct play")
    }

    @Test func whatADeckIsDoing() {
        #expect(PlayerText.activity(DeckActivity(.playing)) == "Playing")
        #expect(PlayerText.activity(DeckActivity(.playing, onAddOn: true)) == "Playing in VLC")
        #expect(PlayerText.activity(DeckActivity(.paused, onAddOn: true)) == "Paused")
        #expect(PlayerText.activity(DeckActivity(.waiting, waitingFor: .fillingBuffer)) == "Buffering (filling buffer)")
        #expect(PlayerText.activity(DeckActivity(.waiting, onAddOn: true, waitingFor: .waitingForScreen))
                == "Buffering in VLC (waiting for the screen)")
        #expect(PlayerText.activity(DeckActivity(.waiting)) == "Buffering")
        #expect(PlayerText.activity(DeckActivity(nil)) == "Unknown")
    }

    @Test func theDiagnosticsLine() {
        #expect(PlayerText.diagnostics(activity: DeckActivity(.playing), secondsBehindLive: 1.26, position: 600,
                                       conversionReasons: "container not supported", nextBuffered: 42.7)
                == "Playing · 1.3 s behind live · at 0:10:00 · transcoding: container not supported · next programme: 42 s buffered")
        #expect(PlayerText.diagnostics(activity: DeckActivity(.paused), secondsBehindLive: 0, position: 5,
                                       conversionReasons: nil, nextBuffered: nil)
                == "Paused · 0.0 s behind live · at 0:00:05 · no transcoding")
    }
}
