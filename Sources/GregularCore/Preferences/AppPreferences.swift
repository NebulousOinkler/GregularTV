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
/// channel, streaming quality, schedule code, the diagnostics, commercials,
/// editing-page and frame-rate switches, and the viewer's custom channels and set times) and **never**
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
        static let matchesFrameRate = "matchesFrameRate"
    }

    private let defaults: any PreferenceStorage

    public init(storage: any PreferenceStorage) {
        defaults = storage
    }

    public init(defaults: UserDefaults = .standard) {
        self.init(storage: defaults)
    }

    /// What's kept under `key`, if it's a `T`.
    private func value<T>(_ key: String) -> T? {
        defaults.object(forKey: key) as? T
    }

    /// The codes kept under `key`, each read by `read`. One that can't be read is left out.
    private func codes<T>(_ key: String, _ read: (String) -> T?) -> [T] {
        (value(key) as [String]? ?? []).compactMap(read)
    }

    /// The channel to open on launch.
    public var lastChannelNumber: Int? {
        get { value(Key.lastChannelNumber) }
        nonmutating set { defaults.set(newValue, forKey: Key.lastChannelNumber) }
    }

    public var streamingQuality: StreamingQuality {
        get { (value(Key.streamingQuality) as String?).flatMap(StreamingQuality.init(rawValue:)) ?? .auto }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Key.streamingQuality) }
    }

    /// "Show playback diagnostics" in Settings. Off by default.
    public var showsDiagnostics: Bool {
        get { value(Key.showsDiagnostics) ?? false }
        nonmutating set { defaults.set(newValue, forKey: Key.showsDiagnostics) }
    }

    /// "Play commercials" in Settings. On by default; off leaves breaks blank.
    public var playsCommercials: Bool {
        get { value(Key.playsCommercials) ?? true }
        nonmutating set { defaults.set(newValue, forKey: Key.playsCommercials) }
    }

    /// Channels made in Settings, stored as their channel codes.
    public var customChannels: [CustomChannel] {
        get { codes(Key.customChannels, CustomChannel.init(code:)) }
        nonmutating set { defaults.set(newValue.map(\.code), forKey: Key.customChannels) }
    }

    /// Set times made in Settings, stored as their codes.
    public var setTimes: [SetTimes] {
        get { codes(Key.setTimes, SetTimes.init(code:)) }
        nonmutating set { defaults.set(newValue.map(\.code), forKey: Key.setTimes) }
    }

    /// "Match frame rate" in Settings (Apple TV): whether the TV switches to
    /// what's on screen's frame rate and dynamic range. Off by default.
    public var matchesFrameRate: Bool {
        get { value(Key.matchesFrameRate) ?? false }
        nonmutating set { defaults.set(newValue, forKey: Key.matchesFrameRate) }
    }

    /// "Edit from a phone or computer" in Settings: whether Settings offers
    /// the editing page on the home network. Off by default.
    public var allowsEditingPage: Bool {
        get { value(Key.allowsEditingPage) ?? false }
        nonmutating set { defaults.set(newValue, forKey: Key.allowsEditingPage) }
    }

    /// The shared schedule code. Nil until first launch picks one.
    public var scheduleCode: ScheduleCode? {
        get { (value(Key.scheduleCode) as String?).flatMap(ScheduleCode.init) }
        nonmutating set { defaults.set(newValue?.description, forKey: Key.scheduleCode) }
    }
}
