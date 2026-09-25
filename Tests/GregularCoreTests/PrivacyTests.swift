import Foundation
import Testing
@testable import GregularCore

/// Guards the privacy rules in PLAN.md §3.
struct PrivacyTests {
    @Test func preferencesStoreOnlyClientSettings() throws {
        let suite = "GregularTVTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let prefs = AppPreferences(defaults: defaults)
        #expect(prefs.lastChannelNumber == nil)
        prefs.lastChannelNumber = 7
        #expect(AppPreferences(defaults: defaults).lastChannelNumber == 7)
        #expect(prefs.streamingQuality == .auto)
        prefs.streamingQuality = .hd720
        #expect(AppPreferences(defaults: defaults).streamingQuality == .hd720)
        #expect(prefs.scheduleCode == nil)
        prefs.scheduleCode = ScheduleCode("7KQM2-X9PDA")
        #expect(AppPreferences(defaults: defaults).scheduleCode == ScheduleCode("7KQM2-X9PDA"))
        #expect(prefs.showsDiagnostics == false)
        prefs.showsDiagnostics = true
        #expect(AppPreferences(defaults: defaults).showsDiagnostics)
        #expect(prefs.playsCommercials)
        prefs.playsCommercials = false
        #expect(AppPreferences(defaults: defaults).playsCommercials == false)
        #expect(defaults.persistentDomain(forName: suite)?.keys.sorted()
                == ["lastChannelNumber", "playsCommercials", "scheduleCode", "showsDiagnostics", "streamingQuality"])
    }

    #if os(macOS)
    /// Runs `scripts/privacy-check.sh`, the same check the app build runs,
    /// so `swift test` also fails if persistence APIs creep in.
    @Test func sourceUsesNoPersistenceOutsideAllowedFiles() throws {
        let repo = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let process = Process()
        process.executableURL = repo.appendingPathComponent("scripts/privacy-check.sh")
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()
        let log = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        #expect(process.terminationStatus == 0, "\(log)")
    }
    #endif

    // The Keychain round-trip test lives in App/GregularTVTests, because it needs an app host.
}
