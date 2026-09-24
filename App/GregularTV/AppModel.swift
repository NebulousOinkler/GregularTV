import Foundation
import GregularTVCore
import Observation

/// The app's top-level state: signed out, loading the library, or watching.
///
/// The library and schedules live only in this object's memory. On relaunch
/// they're fetched again (PLAN.md §3).
@MainActor @Observable
final class AppModel {
    enum Phase {
        case launching
        case signedOut
        case loading
        case watching(ChannelSurfer)
        case failed(String)
    }

    private(set) var phase: Phase = .launching
    /// Why the user is back at sign-in, if it wasn't their choice.
    private(set) var signedOutReason: String?
    /// Decides every channel's running order. Shown and editable in Settings;
    /// the same code gives the same schedule on any Apple TV with the same library.
    private(set) var scheduleCode: ScheduleCode
    /// "Show playback diagnostics" in Settings.
    private(set) var showsDiagnostics: Bool
    /// "Play commercials" in Settings. Off leaves every break blank, with the
    /// same programme times, so the schedule code still means the same schedule.
    private(set) var playsCommercials: Bool
    let identity: ClientIdentity
    private let store: any CredentialStore
    private let preferences: AppPreferences
    private var client: JellyfinClient?
    /// The library, in memory only, so a new schedule code can rebuild the
    /// channels without fetching it again.
    private var library: [MediaItem] = []
    /// The commercials (gap filler clips), in memory only. Empty when there's
    /// no commercials library on the server.
    private var commercials: [MediaItem] = []
    /// What was found in the commercials library, in plain words. Shown in
    /// Settings with diagnostics on, so a missing or unscanned library is easy to spot.
    private(set) var commercialsStatus: String?

    init(store: any CredentialStore = KeychainStore(), preferences: AppPreferences = AppPreferences()) {
        self.store = store
        self.preferences = preferences
        identity = ClientIdentity(deviceID: store.deviceID())
        showsDiagnostics = preferences.showsDiagnostics
        playsCommercials = preferences.playsCommercials
        if let saved = preferences.scheduleCode {
            scheduleCode = saved
        } else {
            scheduleCode = .random()   // first launch
            preferences.scheduleCode = scheduleCode
        }
    }

    /// Reconnect with saved credentials, or ask the user to sign in.
    func launch() async {
        guard let credentials = store.loadCredentials() else {
            phase = .signedOut
            return
        }
        await connect(credentials)
    }

    func didSignIn(_ credentials: Credentials) async {
        signedOutReason = nil
        // If the Keychain write fails, still carry on for this session.
        try? store.saveCredentials(credentials)
        await connect(credentials)
    }

    func setStreamingQuality(_ quality: StreamingQuality) {
        preferences.streamingQuality = quality
        if case .watching(let surfer) = phase { surfer.player.setQuality(quality) }
    }

    func setShowsDiagnostics(_ show: Bool) {
        showsDiagnostics = show
        preferences.showsDiagnostics = show
        if case .watching(let surfer) = phase { surfer.player.diagnosticsEnabled = show }
    }

    /// Rebuilds every channel with or without commercials, and re-tunes the
    /// current channel. Programme times don't change.
    func setPlaysCommercials(_ plays: Bool) {
        guard plays != playsCommercials else { return }
        playsCommercials = plays
        preferences.playsCommercials = plays
        guard case .watching(let surfer) = phase, let client else { return }
        surfer.player.stop()
        phase = watch(library: library, commercials: commercials, client: client,
                      preferring: surfer.player.schedule.channel.number)
    }

    /// Rebuilds every channel from the new code and re-tunes the current channel.
    func setScheduleCode(_ code: ScheduleCode) {
        guard code != scheduleCode else { return }
        scheduleCode = code
        preferences.scheduleCode = code
        guard case .watching(let surfer) = phase, let client else { return }
        surfer.player.stop()
        phase = watch(library: library, commercials: commercials, client: client,
                      preferring: surfer.player.schedule.channel.number)
    }

    func signOut() async {
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
    private func loadCommercials(client: JellyfinClient) async -> [MediaItem] {
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
            found = try await client.fetchLibrary(named: name)
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

    /// Builds every channel's schedule from the library and the schedule code,
    /// and starts watching: the preferred channel, or the lowest-numbered one
    /// if that one is gone or empty.
    private func watch(library: [MediaItem], commercials: [MediaItem], client: JellyfinClient,
                       preferring preferred: Int?) -> Phase {
        guard var channels = try? ChannelLineup.bundled()
            .schedules(for: library, fillerPool: commercials, code: scheduleCode, playsCommercials: playsCommercials)
        else {
            return .failed("channels.json couldn't be read.")
        }
        #if DEBUG
        channels = DebugOptions.apply(to: channels, items: library, fillerPool: playsCommercials ? commercials : [])
        #endif
        let navigator = ChannelNavigator(numbers: channels.map(\.channel.number))
        guard let number = navigator.startingChannel(preferred: preferred),
              let channel = channels.first(where: { $0.channel.number == number })
        else {
            return .failed("None of the channels in channels.json match anything in your library.")
        }
        preferences.lastChannelNumber = number
        let surfer = ChannelSurfer(channels: channels, startingWith: channel, client: client, preferences: preferences)
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
            library = try await client.fetchLibrary()
            commercials = await loadCommercials(client: client)
            phase = watch(library: library, commercials: commercials, client: client,
                          preferring: preferences.lastChannelNumber)
        } catch JellyfinError.unauthorized {
            sessionExpired()
        } catch {
            phase = .failed(FriendlyError.message(for: error))
        }
    }
}
