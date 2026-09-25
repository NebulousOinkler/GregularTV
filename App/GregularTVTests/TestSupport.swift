import Foundation
import GregularCore
import GregularJellyfin
@testable import GregularScreens
@testable import GregularTV

/// The app's tests play on real AVFoundation decks, as the app does.
extension ChannelPlayer {
    convenience init(schedule: ChannelSchedule, streams: any StreamSource, quality: StreamingQuality) {
        self.init(schedule: schedule, streams: streams, quality: quality, decks: AVPlayerDeck.pair())
    }
}

extension ChannelSurfer {
    convenience init(channels: [ChannelSchedule], startingWith channel: ChannelSchedule,
                     streams: any StreamSource, preferences: AppPreferences) {
        self.init(channels: channels, startingWith: channel, streams: streams, preferences: preferences,
                  decks: AVPlayerDeck.pair())
    }
}

extension JellyfinClient {
    /// A client for a server that doesn't exist, whose every reply comes from `transport`.
    static func testing(_ transport: any HTTPTransport) -> JellyfinClient {
        JellyfinClient(credentials: Credentials(serverURL: URL(string: "https://tv.invalid")!, userID: "u", accessToken: "t"),
                       identity: ClientIdentity(deviceID: "test"), transport: transport)
    }
}

extension AppPreferences {
    /// Preferences of their own, so tests never share them (or touch the app's).
    static func testing() -> AppPreferences {
        AppPreferences(defaults: UserDefaults(suiteName: "GregularTVTests-\(UUID())")!)
    }
}

extension ChannelSchedule {
    /// Test channels numbered `numbers` (each seeded with its number), all
    /// playing `items`, with `ads` as commercials if there are any.
    static func testing(_ numbers: [Int] = [1], strategy: String = "derangement", epoch: Date? = nil,
                        padTo: Int? = nil, items: [MediaItem], ads: [MediaItem] = [],
                        playsCommercials: Bool = true) throws -> [ChannelSchedule] {
        let channels = numbers.map { n in
            var fields = [#""number": \#(n)"#, #""name": "C\#(n)""#, #""source": { "type": "all" }"#,
                          #""strategy": "\#(strategy)""#, #""seed": \#(n)"#]
            if let padTo { fields.append(#""padTo": \#(padTo)"#) }
            if !ads.isEmpty { fields.append(#""filler": "derangement""#) }
            if let epoch { fields.append(#""epoch": "\#(ISO8601DateFormatter().string(from: epoch))""#) }
            return "{ " + fields.joined(separator: ", ") + " }"
        }
        return try ChannelLineup.load(from: Data("[\(channels.joined(separator: ","))]".utf8))
            .schedules(for: items, fillerPool: ads, playsCommercials: playsCommercials)
    }
}

/// Waits, checking every 10 ms, until `condition` holds or `seconds` pass.
@MainActor func waitUntil(_ seconds: TimeInterval, _ condition: () -> Bool) async throws {
    let deadline = Date.now.addingTimeInterval(seconds)
    while !condition(), Date.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
}

extension ChannelPlayer.Status {
    var isFailed: Bool { if case .failed = self { true } else { false } }
    var isBetweenProgrammes: Bool { if case .betweenProgrammes = self { true } else { false } }
}
