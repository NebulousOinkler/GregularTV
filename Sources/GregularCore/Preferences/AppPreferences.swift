import Foundation

/// The app's only use of `UserDefaults`. It holds client preferences (last
/// channel, streaming quality, schedule code, diagnostics and commercials
/// switches, and the viewer's custom channels and set times) and **never**
/// anything fetched from the server (PLAN.md §3). Custom channels and set
/// times are kept as their codes: what the viewer typed or picked (names,
/// numbers, times, and perhaps a genre, series or tag name), nothing more.
public struct AppPreferences: @unchecked Sendable {
    private enum Key {
        static let lastChannelNumber = "lastChannelNumber"
        static let streamingQuality = "streamingQuality"
        static let scheduleCode = "scheduleCode"
        static let showsDiagnostics = "showsDiagnostics"
        static let playsCommercials = "playsCommercials"
        static let customChannels = "customChannels"
        static let setTimes = "setTimes"
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The channel to open on launch.
    public var lastChannelNumber: Int? {
        get { defaults.object(forKey: Key.lastChannelNumber) as? Int }
        nonmutating set { defaults.set(newValue, forKey: Key.lastChannelNumber) }
    }

    public var streamingQuality: StreamingQuality {
        get { defaults.string(forKey: Key.streamingQuality).flatMap(StreamingQuality.init(rawValue:)) ?? .auto }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Key.streamingQuality) }
    }

    /// "Show playback diagnostics" in Settings. Off by default.
    public var showsDiagnostics: Bool {
        get { defaults.bool(forKey: Key.showsDiagnostics) }
        nonmutating set { defaults.set(newValue, forKey: Key.showsDiagnostics) }
    }

    /// "Play commercials" in Settings. On by default; off leaves breaks blank.
    public var playsCommercials: Bool {
        get { defaults.object(forKey: Key.playsCommercials) as? Bool ?? true }
        nonmutating set { defaults.set(newValue, forKey: Key.playsCommercials) }
    }

    /// Channels made in Settings, stored as their channel codes.
    public var customChannels: [CustomChannel] {
        get { (defaults.stringArray(forKey: Key.customChannels) ?? []).compactMap(CustomChannel.init(code:)) }
        nonmutating set { defaults.set(newValue.map(\.code), forKey: Key.customChannels) }
    }

    /// Set times made in Settings, stored as their codes.
    public var setTimes: [SetTimes] {
        get { (defaults.stringArray(forKey: Key.setTimes) ?? []).compactMap(SetTimes.init(code:)) }
        nonmutating set { defaults.set(newValue.map(\.code), forKey: Key.setTimes) }
    }

    /// The shared schedule code. Nil until first launch picks one.
    public var scheduleCode: ScheduleCode? {
        get { defaults.string(forKey: Key.scheduleCode).flatMap(ScheduleCode.init) }
        nonmutating set { defaults.set(newValue?.description, forKey: Key.scheduleCode) }
    }
}
