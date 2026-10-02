import Foundation
import GregularCore
import GregularScreens

// Fixtures for both the package's GregularScreensTests and the app's
// GregularTVTests: Package.swift and the Xcode project each compile this
// folder into their tests, so these are written once.

extension ChannelSchedule {
    /// Test channels numbered `numbers` (each seeded with its number), all
    /// playing `items`, with `ads` as commercials if there are any.
    static func testing(_ numbers: [Int] = [1], strategy: String = "shuffled-shows", epoch: Date? = nil,
                        padTo: Int? = nil, items: [MediaItem], ads: [MediaItem] = [],
                        playsCommercials: Bool = true) throws -> [ChannelSchedule] {
        let channels = numbers.map { n in
            var fields = [#""number": \#(n)"#, #""name": "C\#(n)""#, #""source": { "type": "all" }"#,
                          #""strategy": "\#(strategy)""#, #""seed": \#(n)"#]
            if let padTo { fields.append(#""padTo": \#(padTo)"#) }
            if !ads.isEmpty { fields.append(#""filler": "shuffle""#) }
            if let epoch { fields.append(#""epoch": "\#(ISO8601DateFormatter().string(from: epoch))""#) }
            return "{ " + fields.joined(separator: ", ") + " }"
        }
        return try ChannelLineup.load(from: Data("[\(channels.joined(separator: ","))]".utf8))
            .schedules(for: items, fillerPool: ads, playsCommercials: playsCommercials)
    }
}

extension AppPreferences {
    /// Preferences of their own, in memory, so tests never share them (or
    /// touch the app's), and run the same on every platform.
    static func testing() -> AppPreferences {
        AppPreferences(storage: MemoryPreferences())
    }
}

/// Preferences held in memory only, for tests.
final class MemoryPreferences: PreferenceStorage, @unchecked Sendable {
    private var values: [String: Any] = [:]

    func object(forKey key: String) -> Any? { values[key] }
    func set(_ value: Any?, forKey key: String) { values[key] = value }
}

extension ChannelPlayer.Status {
    var isFailed: Bool { if case .failed = self { true } else { false } }
    var isBetweenProgrammes: Bool { if case .betweenProgrammes = self { true } else { false } }
}

/// Waits, checking every 10 ms, until `condition` holds or `seconds` pass.
@MainActor func waitUntil(_ seconds: TimeInterval, _ condition: () -> Bool) async throws {
    let deadline = Date.now.addingTimeInterval(seconds)
    while !condition(), Date.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
}
