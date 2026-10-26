import AVFoundation
import Foundation
import SwiftVLC
import Testing
@testable import GregularTV

/// The players start as the app sets them up, not with their defaults.
@MainActor struct VLCSetupTests {
    /// VLC starts with the app's own arguments: if libVLC refused one,
    /// `VLCItem` would quietly fall back to a VLC that logs, with a
    /// one-second network buffer.
    @Test func vlcTakesTheAppsArguments() throws {
        #expect(VLCItem.arguments.contains("--quiet"))
        #expect(VLCItem.arguments.contains("--network-caching=3000"))
        _ = try VLCInstance(arguments: VLCItem.arguments)
    }

    /// Apple TV's own player waits until it can play on, rather than starting into a stall.
    @Test func avFoundationWaitsRatherThanStalls() {
        #expect(TVDeck().avPlayer.automaticallyWaitsToMinimizeStalling)
    }
}
