import Foundation
import Testing

/// The logic, the Jellyfin connection and the app only depend on each other
/// the allowed ways (see `scripts/layer-check.sh` and Package.swift).
struct LayerTests {
    @Test func importsStayWithinTheirLayer() throws {
        let repo = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let process = Process()
        process.executableURL = repo.appendingPathComponent("scripts/layer-check.sh")
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()
        let log = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        #expect(process.terminationStatus == 0, "\(log)")
    }
}
