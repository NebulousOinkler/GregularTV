import Foundation
import SwiftVLC
import Testing
@testable import GregularTV

/// VLC starts with the app's own arguments, not libVLC's defaults: if it
/// refused one, `VLCItem` would quietly fall back to a VLC that logs.
@MainActor struct VLCSetupTests {
    @Test func vlcTakesTheAppsArguments() throws {
        #expect(VLCItem.arguments.contains("--quiet"))
        _ = try VLCInstance(arguments: VLCItem.arguments)
    }
}
