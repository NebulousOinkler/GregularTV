import Foundation
import GregularCore
import GregularJellyfin
import Observation

/// The app's top-level state: signed out, loading the library, or watching.
///
/// This is where the three parts meet. It signs in to Jellyfin
/// (`GregularJellyfin`), then hands the client on only as Core's interfaces:
/// a `MediaLibrary` to load programmes and commercials, and a `StreamSource`
/// to the player. Nothing below it (the player, the guide, Settings) knows
/// which server it's talking to.
///
/// The library and schedules live only in this object's memory. On relaunch
/// they're fetched again (PLAN.md §3).
@MainActor @Observable
public final class AppModel {
    public enum Phase {
        case launching
        case signedOut
        case loading
        case watching(ChannelSurfer)
        case failed(String)
    }

    public private(set) var phase: Phase = .launching
    /// Why the user is back at sign-in, if it wasn't their choice.
    public private(set) var signedOutReason: String?
    /// Decides every channel's running order. Shown and editable in Settings;
    /// the same code gives the same schedule on any device with the same library.
    public private(set) var scheduleCode: ScheduleCode
    /// "Show playback diagnostics" in Settings.
    public private(set) var showsDiagnostics: Bool
    /// "Play commercials" in Settings. Off leaves every break blank, with the
    /// same programme times, so the schedule code still means the same schedule.
    public private(set) var playsCommercials: Bool
    /// Channels made in Settings, added to the bundled line-up.
    public private(set) var customChannels: [CustomChannel]
    /// Set times made in Settings, laid over their channels.
    public private(set) var setTimes: [SetTimes]
    public let identity: ClientIdentity
    private let store: any CredentialStore
    private let preferences: AppPreferences
    private let makeDecks: @MainActor () -> [any PlayerDeck]
    private var client: JellyfinClient?
    /// The library, in memory only, so a new schedule code can rebuild the
    /// channels without fetching it again.
    private var library: [MediaItem] = []
    /// The commercials (gap filler clips), in memory only. Empty when there's
    /// no commercials library on the server.
    private var commercials: [MediaItem] = []
    /// What was found in the commercials library, in plain words. Shown in
    /// Settings with diagnostics on, so a missing or unscanned library is easy to spot.
    public private(set) var commercialsStatus: String?

    /// - Parameters:
    ///   - deviceName: the kind of device, as Jellyfin lists it, such as
    ///     "Apple TV" (never the name the user gave their device).
    ///   - makeDecks: the two video decks for each channel player
    ///     (see `PlayerDeck`): AVFoundation on Apple TV.
    public init(deviceName: String, store: any CredentialStore, preferences: AppPreferences = AppPreferences(),
                makeDecks: @escaping @MainActor () -> [any PlayerDeck]) {
        self.makeDecks = makeDecks
        self.store = store
        self.preferences = preferences
        identity = ClientIdentity(deviceID: store.deviceID(), deviceName: deviceName)
        showsDiagnostics = preferences.showsDiagnostics
        playsCommercials = preferences.playsCommercials
        customChannels = preferences.customChannels
        setTimes = preferences.setTimes
        if let saved = preferences.scheduleCode {
            scheduleCode = saved
        } else {
            scheduleCode = .random()   // first launch
            preferences.scheduleCode = scheduleCode
        }
    }

    /// Reconnect with saved credentials, or ask the user to sign in.
    public func launch() async {
        guard let credentials = store.loadCredentials() else {
            phase = .signedOut
            return
        }
        await connect(credentials)
    }

    /// The sign-in steps for the sign-in screen. Signing in there carries on here.
    public func makeLoginModel() -> LoginModel {
        LoginModel(identity: identity) { [weak self] credentials in await self?.didSignIn(credentials) }
    }

    public func didSignIn(_ credentials: Credentials) async {
        signedOutReason = nil
        // If the Keychain write fails, still carry on for this session.
        try? store.saveCredentials(credentials)
        await connect(credentials)
    }

    public func setStreamingQuality(_ quality: StreamingQuality) {
        preferences.streamingQuality = quality
        if case .watching(let surfer) = phase { surfer.player.setQuality(quality) }
    }

    public func setShowsDiagnostics(_ show: Bool) {
        showsDiagnostics = show
        preferences.showsDiagnostics = show
        if case .watching(let surfer) = phase { surfer.player.diagnosticsEnabled = show }
    }

    /// Rebuilds every channel with or without commercials. Programme times
    /// don't change, so the current channel only re-tunes during a break.
    public func setPlaysCommercials(_ plays: Bool) {
        guard plays != playsCommercials else { return }
        playsCommercials = plays
        preferences.playsCommercials = plays
        rebuildChannels()
    }

    /// Rebuilds every channel from the new code, which re-tunes the current channel.
    public func setScheduleCode(_ code: ScheduleCode) {
        guard code != scheduleCode else { return }
        scheduleCode = code
        preferences.scheduleCode = code
        rebuildChannels()
    }

    // MARK: - Your channels and set times

    /// An editor for a new custom channel, or for `channel`. Nil until the
    /// library has loaded (its genres, series and tags are the choices).
    public func makeChannelEditor(editing channel: CustomChannel? = nil) -> ChannelEditorModel? {
        guard case .watching = phase, let lineup = lineup(custom: customChannels.filter { $0 != channel }, setTimes: [])
        else { return nil }
        return ChannelEditorModel(editing: channel, library: library, lineup: lineup, code: scheduleCode)
    }

    /// An editor for the set times on channel `number` (new, or the ones it has).
    public func makeSetTimesEditor(forChannel number: Int) -> SetTimesEditorModel? {
        guard case .watching = phase, let lineup = lineup(custom: customChannels, setTimes: []),
              let channel = lineup.channels.first(where: { $0.number == number }) else { return nil }
        return SetTimesEditorModel(channel: channel, editing: setTimes.first { $0.channelNumber == number },
                                   library: library, lineup: lineup, code: scheduleCode)
    }

    /// A channel set times can go on, for Settings: every channel in the
    /// line-up, with its set times if it has some.
    public struct SetTimesChannel: Identifiable, Sendable {
        public let number: Int
        /// "2  Comedy".
        public let title: String
        public let setTimes: SetTimes?
        /// The set times' names this library doesn't have, so they never air.
        public let missing: [String]
        public var id: Int { number }

        /// The line under its row: what's set, and anything that won't air,
        /// "Far Signal · Not in your library: Orbit & Pip". Nil with no set times.
        public var detail: String? {
            guard let setTimes else { return nil }
            let missingNote = missing.isEmpty ? nil : "Not in your library: \(missing.joined(separator: ", "))"
            return [setTimes.summary, missingNote].compactMap { $0 }.joined(separator: " · ")
        }
    }

    /// Every channel set times can go on, in order: those on air with this
    /// library (a themed channel without enough variety is hidden, see
    /// `ChannelVariety`), and any that already have set times, to change or delete them.
    public var setTimesChannels: [SetTimesChannel] {
        let onAir: Set<Int>? = if case .watching(let surfer) = phase { Set(surfer.channels.map(\.channel.number)) } else { nil }
        let channels = (lineup(custom: customChannels, setTimes: [])?.channels ?? []).filter { channel in
            onAir.map { $0.contains(channel.number) } ?? true || setTimes.contains { $0.channelNumber == channel.number }
        }
        return channels.map { channel in
            let times = setTimes.first { $0.channelNumber == channel.number }
            return SetTimesChannel(number: channel.number, title: "\(channel.number)  \(channel.name)", setTimes: times,
                                   // Nothing's known to be missing until the library has loaded.
                                   missing: library.isEmpty ? [] : (times?.programmes ?? []).filter { !$0.isAvailable(in: library) }.map(\.match.title))
        }
    }

    /// Saves `channel` (in place of `original`, when editing) and rebuilds the
    /// channels. Returns why it couldn't be saved, or nil.
    @discardableResult
    public func save(_ channel: CustomChannel, replacing original: CustomChannel? = nil) -> String? {
        let channels = (customChannels.filter { $0 != original } + [channel]).sorted { $0.number < $1.number }
        // Set times on the channel go with it to its new number.
        let moved = setTimes.map { times in
            guard let original, times.channelNumber == original.number else { return times }
            var moved = times
            moved.channelNumber = channel.number
            return moved
        }
        return apply(custom: channels, setTimes: moved)
    }

    /// Saves set times (in place of `original`, when editing) and rebuilds the
    /// channels. Returns why they couldn't be saved, or nil.
    @discardableResult
    public func save(_ setTimes: SetTimes, replacing original: SetTimes? = nil) -> String? {
        let all = (self.setTimes.filter { $0 != original } + [setTimes]).sorted { $0.channelNumber < $1.channelNumber }
        return apply(custom: customChannels, setTimes: all)
    }

    /// Adds the channel a channel code describes. Returns why it couldn't, or nil.
    public func addChannel(code: String) -> String? {
        guard let channel = CustomChannel(code: code) else {
            return "That isn't a channel code. Check it against the Settings it came from."
        }
        return save(channel)
    }

    /// Adds the set times a set-times code describes. Returns why it couldn't, or nil.
    public func addSetTimes(code: String) -> String? {
        guard let setTimes = SetTimes(code: code) else {
            return "That isn't a set-times code. Check it against the Settings it came from."
        }
        return save(setTimes, replacing: self.setTimes.first { $0.channelNumber == setTimes.channelNumber })
    }

    /// Deletes a custom channel, and any set times on it. Ask the editor's
    /// `deleteConfirmation` first.
    public func delete(_ channel: CustomChannel) {
        _ = apply(custom: customChannels.filter { $0 != channel },
                  setTimes: setTimes.filter { $0.channelNumber != channel.number })
    }

    /// Ask the editor's `deleteConfirmation` first.
    public func delete(_ setTimes: SetTimes) {
        _ = apply(custom: customChannels, setTimes: self.setTimes.filter { $0 != setTimes })
    }

    /// Checks, saves and uses the viewer's channels and set times. Returns
    /// why they can't be used, or nil.
    private func apply(custom: [CustomChannel], setTimes: [SetTimes]) -> String? {
        do {
            _ = try ChannelLineup.bundled().adding(custom, setTimes: setTimes)
        } catch {
            return "\(error)"
        }
        customChannels = custom
        self.setTimes = setTimes
        preferences.customChannels = custom
        preferences.setTimes = setTimes
        rebuildChannels()
        return nil
    }

    /// The bundled channels with `custom` and `setTimes` added. One that no
    /// longer fits (a newer app took its number) is left out, not an error.
    private func lineup(custom: [CustomChannel], setTimes: [SetTimes]) -> ChannelLineup? {
        guard var lineup = try? ChannelLineup.bundled() else { return nil }
        for channel in custom { lineup = (try? lineup.adding([channel])) ?? lineup }
        for times in setTimes { lineup = (try? lineup.adding([], setTimes: [times])) ?? lineup }
        return lineup
    }

    /// Rebuilds every channel after a setting changed. The channel playing
    /// only re-tunes if what's on it now changed (`ChannelSurfer.replaceChannels`),
    /// so changing another channel's set times never re-buffers it.
    /// Programme times only change if the code did.
    private func rebuildChannels() {
        guard case .watching(let surfer) = phase, let client else { return }
        if let channels = schedules(), surfer.replaceChannels(channels) { return }
        // Nothing to watch any more: start again, which says why.
        surfer.player.stop()
        phase = watch(library: library, commercials: commercials, streams: client,
                      preferring: surfer.player.schedule.channel.number)
    }

    /// Ask this before `signOut()`.
    public var signOutConfirmation: Confirmation {
        Confirmation(action: "Sign Out", question: "Sign out of Jellyfin?",
                     detail: "You'll need to sign in again to watch. Your channels and set times stay on this \(identity.deviceName).")
    }

    public func signOut() async {
        if case .watching(let surfer) = phase { surfer.player.stop() }
        library = []
        commercials = []
        commercialsStatus = nil
        await client?.signOut(clearing: store)
        client = nil
        phase = .signedOut
    }

    // MARK: - Private

    /// The clips from the commercials library named in `channels.json`. If
    /// there's no such library, or it can't be read, the result is empty:
    /// the "Up next" card fills the gaps and everything else works as usual.
    private func loadCommercials(from source: any MediaLibrary) async -> [MediaItem] {
        #if DEBUG
        if DebugOptions.usesPretendCommercials {
            commercialsStatus = "Using pretend commercials (debug option)."
            return DebugOptions.pretendCommercials(from: library)
        }
        #endif
        guard let name = (try? ChannelLineup.bundled())?.commercialsLibrary else {
            commercialsStatus = "No commercials library is named in channels.json."
            return []
        }
        let found: [MediaItem]?
        do {
            found = try await source.fetchCollection(named: name)
        } catch {
            commercialsStatus = "Couldn't load the \u{201C}\(name)\u{201D} library, so breaks show the Up Next card."
            return []
        }
        guard let found else {
            commercialsStatus = "There's no library called \u{201C}\(name)\u{201D}, or this user can't see it. Breaks show the Up Next card."
            return []
        }
        let usable = found.filter { $0.duration > 0 }
        commercialsStatus = switch (found.count, usable.count) {
        case (0, _):
            "The \u{201C}\(name)\u{201D} library has no videos in it yet."
        case (let all, 0):
            "The \u{201C}\(name)\u{201D} library has \(all) videos, but Jellyfin doesn't know their lengths yet. Scan the library in Jellyfin."
        case (let all, let usable) where usable < all:
            "\(usable) commercials from \u{201C}\(name)\u{201D}. \(all - usable) more are waiting for a library scan."
        case (_, let usable):
            "\(usable) commercials from \u{201C}\(name)\u{201D}."
        }
        return usable
    }

    /// Every channel's schedule, from the library, the schedule code and the
    /// viewer's channels and set times. Nil if channels.json can't be read.
    private func schedules(library: [MediaItem]? = nil, commercials: [MediaItem]? = nil) -> [ChannelSchedule]? {
        let library = library ?? self.library, commercials = commercials ?? self.commercials
        guard var channels = lineup(custom: customChannels, setTimes: setTimes)?
            .schedules(for: library, fillerPool: commercials, code: scheduleCode, playsCommercials: playsCommercials)
        else { return nil }
        #if DEBUG
        channels = DebugOptions.apply(to: channels, items: library, fillerPool: playsCommercials ? commercials : [])
        #endif
        return channels
    }

    /// Builds every channel's schedule from the library and the schedule code,
    /// and starts watching: the preferred channel, or the lowest-numbered one
    /// if that one is gone or empty.
    private func watch(library: [MediaItem], commercials: [MediaItem], streams: any StreamSource,
                       preferring preferred: Int?) -> Phase {
        guard let channels = schedules(library: library, commercials: commercials) else {
            return .failed("channels.json couldn't be read.")
        }
        let navigator = ChannelNavigator(numbers: channels.map(\.channel.number))
        guard let number = navigator.startingChannel(preferred: preferred),
              let channel = channels.first(where: { $0.channel.number == number })
        else {
            return .failed("None of the channels in channels.json match anything in your library.")
        }
        preferences.lastChannelNumber = number
        let surfer = ChannelSurfer(channels: channels, startingWith: channel, streams: streams, preferences: preferences,
                                   decks: makeDecks())
        surfer.player.onUnauthorized = { [weak self] in self?.sessionExpired() }
        return .watching(surfer)
    }

    /// The server no longer accepts our token. Forget it locally (there's
    /// nothing to revoke) and ask the user to sign in again.
    private func sessionExpired() {
        if case .watching(let surfer) = phase { surfer.player.stop() }
        try? store.deleteCredentials()
        client = nil
        signedOutReason = JellyfinError.unauthorized.localizedDescription
        phase = .signedOut
    }

    private func connect(_ credentials: Credentials) async {
        phase = .loading
        let client = JellyfinClient(credentials: credentials, identity: identity)
        self.client = client
        do {
            try? await client.registerCapabilities()
            library = try await client.fetchProgrammes()
            commercials = await loadCommercials(from: client)
            phase = watch(library: library, commercials: commercials, streams: client,
                          preferring: preferences.lastChannelNumber)
        } catch JellyfinError.unauthorized {
            sessionExpired()
        } catch {
            phase = .failed(FriendlyError.message(for: error))
        }
    }
}
