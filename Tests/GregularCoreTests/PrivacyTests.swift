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
        #expect(prefs.customChannels.isEmpty)
        let custom = CustomChannel(number: 25, name: "Comedy", rule: .genre("Comedy"))
        prefs.customChannels = [custom]
        #expect(AppPreferences(defaults: defaults).customChannels == [custom])
        // Kept as the channel code: only what the viewer typed or picked.
        #expect(defaults.stringArray(forKey: "customChannels") == [custom.code])
        #expect(prefs.setTimes.isEmpty)
        let setTimes = SetTimes(channelNumber: 2, programmes: [FixedProgramme(match: .series("Alpha"), times: [18 * 60])],
                                timeZone: TimeZone(identifier: "America/New_York")!)
        prefs.setTimes = [setTimes]
        #expect(AppPreferences(defaults: defaults).setTimes == [setTimes])
        #expect(defaults.stringArray(forKey: "setTimes") == [setTimes.code])
        #expect(defaults.persistentDomain(forName: suite)?.keys.sorted()
                == ["customChannels", "lastChannelNumber", "playsCommercials", "scheduleCode", "setTimes", "showsDiagnostics", "streamingQuality"])
    }

    #if os(macOS)
    /// Runs `scripts/privacy-check.sh`, the same check the app build runs,
    /// so `swift test` also fails if persistence APIs creep in.
    @Test func sourceUsesNoPersistenceOutsideAllowedFiles() throws {
        let (status, log) = try Fixtures.runScript("privacy-check.sh")
        #expect(status == 0, "\(log)")
    }
    #endif

    // The Keychain round-trip test lives in App/GregularTVTests, because it needs an app host.
}
