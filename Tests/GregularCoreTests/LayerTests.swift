import Foundation
import Testing

/// The logic, the Jellyfin connection and the app only depend on each other
/// the allowed ways (see `scripts/layer-check.sh` and Package.swift).
struct LayerTests {
    #if os(macOS)
    @Test func importsStayWithinTheirLayer() throws {
        let (status, log) = try Fixtures.runScript("layer-check.sh")
        #expect(status == 0, "\(log)")
    }
    #endif
}
