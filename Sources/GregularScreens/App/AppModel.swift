import Foundation
import GregularCore
import GregularJellyfin
import Observation

/// The app's top-level state: the main page (the servers), signing in to
/// one, loading its library, or watching it.
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
    /// What the screens call the kind of server, in text: the one place they
    /// name it, so the rest of the screens don't depend on which it is.
    nonisolated public static let serverName = "Jellyfin"

    public enum Phase {
        case launching
        /// The sign-in screen: the first server, or another from the main page.
        case signedOut
        /// The main page: the servers signed in to, and adding one. The app
        /// opens here. Gone back to from live TV, the channel carries on
        /// playing behind it, ready to go back to without re-tuning.
        case mainPage(over: ChannelSurfer?)
        case loading
        case watching(ChannelSurfer)
        /// A special mode, opened by its keyword in Settings, in place of live TV.
        case special(SpecialModeSession)
        case failed(String)
    }

    /// A server on the main page. Only what the Keychain already holds, and
    /// its name, asked of the server while the page shows and never stored.
    public struct Server: Identifiable, Sendable, Equatable {
        /// The sign-in (server and user).
        public let id: String
        /// "192.168.1.5:8096", "tv.example.com": where it is, without the scheme.
        public let address: String
        /// The name the server gives itself, once it answers; nil until then, or if it doesn't.
        public var name: String?
        /// The one watched last: highlighted, and what Play/Pause watches.
        public let isLastWatched: Bool
        /// Its live TV is still playing behind the main page.
        public var isPlaying = false

        /// The name, or the address until the name is known.
        public var title: String { name ?? address }

        /// "Now playing" or "Watched last", under its name.
        public var badge: String? {
            isPlaying ? "Now playing" : isLastWatched ? "Watched last" : nil
        }
    }

    /// The servers signed in to, the one watched last first.
    public private(set) var servers: [Server] = []

    public private(set) var phase: Phase = .launching
    /// Why the user is back at sign-in, if it wasn't their choice.
    public private(set) var signedOutReason: String?
    /// Something the main page should say, such as a sign-out the server
    /// couldn't be told about. Gone at the next thing done there.
    public private(set) var notice: String?
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
    /// "Edit from a phone or computer" in Settings (off by default): whether
    /// Settings offers the editing page (`EditingPage`) on the home network.
    public private(set) var allowsEditingPage: Bool
    /// "Match frame rate" in Settings (off by default): whether the TV
    /// switches to each programme's frame rate and dynamic range. Only
    /// Apple TV offers it; it's the front end's to apply.
    public private(set) var matchesFrameRate: Bool
    /// The kind of device, as servers list it, such as "Apple TV". Each
    /// sign-in pairs it with a device ID of its own (`ClientIdentity`).
    var deviceName: String { access.deviceName }
    private let access: ServerAccess
    private let store: any CredentialStore
    private let preferences: AppPreferences
    private let makeDecks: @MainActor () -> [any PlayerDeck]
    /// The special modes this front end can open (`SpecialModeScreens.registry`).
    private let specialModes: SpecialModeRegistry
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
    ///   - formats: what the device's player can play.
    ///   - addOnFormats: what the device's add-on player plays as it is (VLC
    ///     on Apple TV), for files its own player can't, or when the viewer
    ///     asks for it; nil if it has none.
    ///   - transport: the platform's network path (`HTTPTransport`).
    ///   - makeDecks: the two video decks for each channel player
    ///     (see `PlayerDeck`): AVFoundation on Apple TV.
    ///   - specialModes: the special modes the front end has screens for; none unless given.
    public init(deviceName: String, formats: PlayableFormats, addOnFormats: PlayableFormats? = nil,
                transport: any HTTPTransport, store: any CredentialStore,
                preferences: AppPreferences, makeDecks: @escaping @MainActor () -> [any PlayerDeck],
                specialModes: SpecialModeRegistry = SpecialModeRegistry()) {
        access = ServerAccess(deviceName: deviceName, formats: formats, addOnFormats: addOnFormats, transport: transport)
        self.makeDecks = makeDecks
        self.specialModes = specialModes
        self.store = store
        self.preferences = preferences
        showsDiagnostics = preferences.showsDiagnostics
        playsCommercials = preferences.playsCommercials
        customChannels = preferences.customChannels
        setTimes = preferences.setTimes
        allowsEditingPage = preferences.allowsEditingPage
        matchesFrameRate = preferences.matchesFrameRate
        if let saved = preferences.scheduleCode {
            scheduleCode = saved
        } else {
            // First launch after installing (preferences go with the app).
            // Secure storage can outlive the app, so a sign-in from before
            // it was deleted would otherwise come back: start with none.
            try? store.deleteAll()
            scheduleCode = .random()
            preferences.scheduleCode = scheduleCode
        }
    }

    #if canImport(Darwin)
    /// On Apple platforms: requests go through URLSession, and preferences
    /// are kept in UserDefaults.
    public convenience init(deviceName: String, formats: PlayableFormats, addOnFormats: PlayableFormats? = nil,
                            store: any CredentialStore, preferences: AppPreferences = AppPreferences(),
                            makeDecks: @escaping @MainActor () -> [any PlayerDeck],
                            specialModes: SpecialModeRegistry = SpecialModeRegistry()) {
        self.init(deviceName: deviceName, formats: formats, addOnFormats: addOnFormats,
                  transport: URLSessionTransport.shared, store: store, preferences: preferences, makeDecks: makeDecks,
                  specialModes: specialModes)
    }
    #endif

    /// The main page, or the sign-in screen if there are no servers yet.
    public func launch() async {
        showMainPage()
    }

    /// Shows the servers, the one watched last highlighted; the sign-in
    /// screen if there are none. From live TV, the channel carries on behind
    /// the page, so going back to it is instant; elsewhere the library stays
    /// in memory, so going back to the same server is still quick.
    public func showMainPage() {
        let saved = store.allCredentials()
        guard !saved.isEmpty else {
            liveTV?.player.stop()
            phase = .signedOut
            return
        }
        let behind = client == nil ? nil : liveTV
        let playingID = behind == nil ? nil : client?.credentials.signInID
        let known = Dictionary(servers.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        servers = saved.enumerated().map { index, credentials in
            Server(credentials, name: known[credentials.signInID] ?? nil, isLastWatched: index == 0,
                   isPlaying: credentials.signInID == playingID)
        }
        phase = .mainPage(over: behind)
    }

    /// The channels being watched: on screen, or playing on behind the main page.
    public var liveTV: ChannelSurfer? {
        switch phase {
        case .watching(let surfer): surfer
        case .mainPage(let surfer): surfer
        default: nil
        }
    }

    /// The main page is showing over live TV.
    public var isOverLiveTV: Bool {
        if case .mainPage(over: _?) = phase { true } else { false }
    }

    /// Asks each server on the main page for its name, to show instead of
    /// its address. In memory only; a server that doesn't answer keeps its address.
    public func loadServerNames() async {
        for server in servers where server.name == nil {
            guard let credentials = credentials(for: server) else { continue }
            let name = try? await access.server(of: credentials).publicInfo().serverName
            guard let name, !name.trimmingCharacters(in: .whitespaces).isEmpty,
                  let index = servers.firstIndex(where: { $0.id == server.id }) else { continue }
            servers[index].name = String(name.prefix(Self.longestServerName))
        }
    }

    /// Names longer than this are cut short, so a server can't push the page around.
    static let longestServerName = 60

    /// Watch `server`. The one playing behind the main page comes back as it
    /// is; the one watched just before goes straight back to live TV from the
    /// library in memory; another loads its library.
    public func watch(_ server: Server) async {
        notice = nil
        guard let credentials = credentials(for: server) else { return showMainPage() }
        try? store.saveCredentials(credentials)   // now the one watched last
        let sameServer = client?.credentials.signInID == credentials.signInID
        if sameServer, case .mainPage(over: let surfer?) = phase {
            phase = .watching(surfer)
            return
        }
        liveTV?.player.stop()   // another server's channel, behind the page
        if let client, sameServer, !library.isEmpty {
            phase = watch(library: library, commercials: commercials, streams: client,
                          preferring: preferences.lastChannelNumber)
        } else {
            await connect(credentials)
        }
    }

    /// The server watched last (Play/Pause on the main page).
    public func watchLastServer() async {
        guard let server = servers.first else { return }
        await watch(server)
    }

    /// The sign-in screen, to add another server.
    public func addServer() {
        notice = nil
        liveTV?.player.stop()
        signedOutReason = nil
        phase = .signedOut
    }

    /// Whether the sign-in screen can go back to the main page (there's a server to go back to).
    public var canCancelSignIn: Bool { !store.allCredentials().isEmpty }

    /// Ask this before `signOut(of:)`, on the main page or in Settings.
    public func signOutConfirmation(for server: Server) -> Confirmation {
        Confirmation(action: "Sign Out", question: "Sign out of \(server.title)?",
                     detail: "You'll need to sign in again to watch it. Your channels and set times stay on this \(deviceName).")
    }

    /// Signs out of `server`: revokes its token and forgets it. Then the main
    /// page, or the sign-in screen if it was the last. If the server couldn't
    /// be told, the main page says how to cancel the sign-in there.
    public func signOut(of server: Server) async {
        notice = nil
        guard let credentials = credentials(for: server) else { return showMainPage() }
        if client?.credentials.signInID == credentials.signInID { forgetLibrary() }
        let revoked = await access.client(for: credentials).signOut(clearing: store)
        servers.removeAll { $0.id == server.id }
        showMainPage()
        guard !revoked else { return }
        let message = "Signed out on this \(deviceName), but \(server.title) couldn't be reached to cancel the sign-in, "
            + "so it still works there. To cancel it, remove this \(deviceName) from the devices in \(Self.serverName)'s dashboard."
        // The sign-in screen, if that was the last server.
        if case .signedOut = phase { signedOutReason = message } else { notice = message }
    }

    private func credentials(for server: Server) -> Credentials? {
        store.allCredentials().first { $0.signInID == server.id }
    }

    /// "192.168.1.5:8096" from "http://192.168.1.5:8096/jellyfin": host, port and any path.
    nonisolated static func address(of url: URL) -> String {
        guard let host = url.host() else { return url.absoluteString }
        let port = url.port.map { ":\($0)" } ?? ""
        let path = url.path() == "/" ? "" : url.path()
        return host + port + path
    }

    /// Drops the library and client for the server being left.
    private func forgetLibrary() {
        liveTV?.player.stop()
        library = []
        commercials = []
        commercialsStatus = nil
        client = nil
    }

    /// The sign-in steps for the sign-in screen. Signing in there carries on here.
    public func makeLoginModel() -> LoginModel {
        LoginModel(access: access) { [weak self] credentials in await self?.didSignIn(credentials) }
    }

    private func didSignIn(_ credentials: Credentials) async {
        // Only from the sign-in screen: a sign-in finishing after it closed is dropped.
        guard case .signedOut = phase else { return }
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

    public func setAllowsEditingPage(_ allows: Bool) {
        allowsEditingPage = allows
        preferences.allowsEditingPage = allows
    }

    public func setMatchesFrameRate(_ matches: Bool) {
        matchesFrameRate = matches
        preferences.matchesFrameRate = matches
    }

    /// Rebuilds every channel from the new code, which re-tunes the current channel.
    public func setScheduleCode(_ code: ScheduleCode) {
        guard code != scheduleCode else { return }
        scheduleCode = code
        preferences.scheduleCode = code
        rebuildChannels()
    }

    /// What was typed where a schedule code goes, in Settings: a schedule
    /// code to use, or a special mode's keyword, which opens it. Returns
    /// what to say if it was neither or the mode can't open, or nil.
    public func enterCode(_ text: String) async -> String? {
        switch CodeEntry(text, specialModes: specialModes) {
        case .schedule(let code):
            setScheduleCode(code)
            return nil
        case .specialMode(let mode):
            return await open(mode) ? nil : SettingsText.specialModeUnavailable
        case nil:
            return SettingsText.badCode
        }
    }

    // MARK: - Special modes

    /// Opens `mode` in place of live TV, with its programmes from the server
    /// being watched. False if it can't: nothing's being watched, or the
    /// server has none of its programmes.
    private func open(_ mode: SpecialMode) async -> Bool {
        guard case .watching = phase, let client else { return false }
        var programmes: [MediaItem]
        switch mode.catalogue {
        case .wholeLibrary:
            programmes = library
        case .libraries(let names):
            programmes = []
            for name in names {
                let found = (try? await client.fetchCollection(named: name, kinds: Set(MediaItem.Kind.allCases))) ?? nil
                programmes += (found ?? []).filter { $0.duration > 0 }
            }
        }
        // Still watching the same server, now it's fetched.
        guard !programmes.isEmpty, case .watching = phase, self.client?.credentials.signInID == client.credentials.signInID
        else { return false }
        liveTV?.player.stop()
        phase = .special(SpecialModeSession(mode: mode, programmes: programmes, formats: client.formats, media: client) { [weak self] session in
            self?.close(session)
        })
        return true
    }

    /// Leaves `session` for live TV, on the channel watched last.
    private func close(_ session: SpecialModeSession) {
        guard case .special(let open) = phase, open === session else { return }
        guard let client else { return showMainPage() }
        phase = watch(library: library, commercials: commercials, streams: client, preferring: preferences.lastChannelNumber)
    }

    // MARK: - Your channels and set times

    /// Your channels and set times as one document, for the editing page.
    public var userChannels: EditingDocument {
        EditingDocument(channels: customChannels, setTimes: setTimes)
    }

    /// Puts `document` in place of your channels and set times, and rebuilds
    /// the channels. Returns why it couldn't, or nil.
    @discardableResult
    public func replaceUserChannels(with document: EditingDocument) -> String? {
        do {
            let (channels, setTimes) = try document.resolved()
            return apply(custom: channels.sorted { $0.number < $1.number }, setTimes: setTimes.sorted { $0.channelNumber < $1.channelNumber })
        } catch {
            return "\(error)"
        }
    }

    /// The library's genres, series, tags, films and years, to pick from
    /// (none until the library has loaded).
    public var libraryChoices: LibraryChoices {
        LibraryChoices(library)
    }

    /// Every channel set times could go on, bundled and custom, by number.
    public var lineupChannels: [Channel] {
        lineup(custom: customChannels, setTimes: [])?.channels ?? []
    }

    /// How many programmes `channel` would play, and its next three hours,
    /// worked out off the main thread.
    public func preview(_ channel: CustomChannel, now: Date = .now) async -> (matching: Int, upcoming: [UpcomingProgramme]) {
        let (library, code, line) = (library, scheduleCode, channel.channel)
        return await Task.detached(priority: .userInitiated) {
            let matching = library.count { line.accepts($0) && $0.duration > 0 }
            guard let schedule = ChannelSchedule(channel: line, items: library, code: code) else { return (matching, []) }
            return (matching, schedule.programmes(from: now, to: now.addingTimeInterval(3 * 3600)).map { UpcomingProgramme($0, now: now) })
        }.value
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

    /// The channels with set times, in order, for Settings to list.
    public var setTimesChannels: [SetTimesChannel] {
        let channels = (lineup(custom: customChannels, setTimes: [])?.channels ?? []).filter { channel in
            setTimes.contains { $0.channelNumber == channel.number }
        }
        return channels.map { channel in
            let times = setTimes.first { $0.channelNumber == channel.number }
            return SetTimesChannel(number: channel.number, title: "\(channel.number)  \(channel.name)", setTimes: times,
                                   // Nothing's known to be missing until the library has loaded.
                                   missing: library.isEmpty ? [] : (times?.programmes ?? []).filter { !$0.isAvailable(in: library) }.map(\.match.title))
        }
    }

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

    /// The server being watched, as the main page lists it.
    public var currentServer: Server? {
        guard let credentials = client?.credentials else { return nil }
        return Server(credentials, name: servers.first { $0.id == credentials.signInID }?.name, isLastWatched: true)
    }

    /// Tries the server watched last again, after a failure.
    public func retry() async {
        if let credentials = client?.credentials ?? store.loadCredentials() {
            await connect(credentials)
        } else {
            showMainPage()
        }
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
            found = try await source.fetchCollection(named: name, kinds: [.video, .movie, .episode])
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
            "The \u{201C}\(name)\u{201D} library has \(all) videos, but \(Self.serverName) doesn't know their lengths yet. Scan the library in \(Self.serverName)."
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
        liveTV?.player.stop()
        if let credentials = client?.credentials { try? store.deleteCredentials(credentials) }
        library = []
        commercials = []
        client = nil
        signedOutReason = JellyfinError.unauthorized.localizedDescription
        phase = .signedOut
    }

    private func connect(_ credentials: Credentials) async {
        liveTV?.player.stop()
        phase = .loading
        let client = access.client(for: credentials)
        self.client = client
        do {
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

private extension AppModel.Server {
    /// A sign-in as the main page lists it: by its address until the server gives its name.
    init(_ credentials: Credentials, name: String?, isLastWatched: Bool, isPlaying: Bool = false) {
        self.init(id: credentials.signInID, address: AppModel.address(of: credentials.serverURL), name: name,
                  isLastWatched: isLastWatched, isPlaying: isPlaying)
    }
}
