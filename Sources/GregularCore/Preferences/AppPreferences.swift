import Foundation

/// Where preferences are kept: `UserDefaults` on Apple platforms, the
/// browser's local storage on the web. Values are an `Int`, `Bool`,
/// `String` or `[String]`, and nil removes one.
public protocol PreferenceStorage: AnyObject {
    func object(forKey key: String) -> Any?
    func set(_ value: Any?, forKey key: String)
}

extension UserDefaults: PreferenceStorage {}

/// The app's only use of `UserDefaults` (or the platform's
/// `PreferenceStorage`). It holds client preferences (last
/// channel, streaming quality, schedule code, the diagnostics, commercials
/// and editing-page switches, and the viewer's custom channels and set times) and **never**
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
        static let allowsEditingPage = "allowsEditingPage"
    }

    private let defaults: any PreferenceStorage

    public init(storage: any PreferenceStorage) {
        defaults = storage
    }

    public init(defaults: UserDefaults = .standard) {
        self.init(storage: defaults)
    }

    /// The channel to open on launch.
    public var lastChannelNumber: Int? {
        get { defaults.object(forKey: Key.lastChannelNumber) as? Int }
        nonmutating set { defaults.set(newValue, forKey: Key.lastChannelNumber) }
    }

    public var streamingQuality: StreamingQuality {
        get { (defaults.object(forKey: Key.streamingQuality) as? String).flatMap(StreamingQuality.init(rawValue:)) ?? .auto }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Key.streamingQuality) }
    }

    /// "Show playback diagnostics" in Settings. Off by default.
    public var showsDiagnostics: Bool {
        get { defaults.object(forKey: Key.showsDiagnostics) as? Bool ?? false }
        nonmutating set { defaults.set(newValue, forKey: Key.showsDiagnostics) }
    }

    /// "Play commercials" in Settings. On by default; off leaves breaks blank.
    public var playsCommercials: Bool {
        get { defaults.object(forKey: Key.playsCommercials) as? Bool ?? true }
        nonmutating set { defaults.set(newValue, forKey: Key.playsCommercials) }
    }

    /// Channels made in Settings, stored as their channel codes.
    public var customChannels: [CustomChannel] {
        get { (defaults.object(forKey: Key.customChannels) as? [String] ?? []).compactMap(CustomChannel.init(code:)) }
        nonmutating set { defaults.set(newValue.map(\.code), forKey: Key.customChannels) }
    }

    /// Set times made in Settings, stored as their codes.
    public var setTimes: [SetTimes] {
        get { (defaults.object(forKey: Key.setTimes) as? [String] ?? []).compactMap(SetTimes.init(code:)) }
        nonmutating set { defaults.set(newValue.map(\.code), forKey: Key.setTimes) }
    }

    /// "Edit from a phone or computer" in Settings: whether Settings offers
    /// the editing page on the home network. Off by default.
    public var allowsEditingPage: Bool {
        get { defaults.object(forKey: Key.allowsEditingPage) as? Bool ?? false }
        nonmutating set { defaults.set(newValue, forKey: Key.allowsEditingPage) }
    }

    /// The shared schedule code. Nil until first launch picks one.
    public var scheduleCode: ScheduleCode? {
        get { (defaults.object(forKey: Key.scheduleCode) as? String).flatMap(ScheduleCode.init) }
        nonmutating set { defaults.set(newValue?.description, forKey: Key.scheduleCode) }
    }
}
