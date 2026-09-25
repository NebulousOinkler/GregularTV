import Foundation
import GregularCore
import Observation

/// Everything the watch screen decides, with nothing about how it's drawn:
/// which overlay is open, when the banner shows and hides, the curtain that
/// fades between a break and the programme, what each remote action does,
/// and the words on the banner, cards and badge. The Apple TV's `WatchView`
/// draws it; another version of the app (such as a web page) would draw the
/// same model its own way.
///
/// **Timers.** The banner's hide timer and the curtain's fades run while the
/// screen is showing: call `runBannerTimer()` whenever `bannerTrigger`
/// changes, and `runCurtain()` whenever `curtainTrigger` changes, cancelling
/// the previous run each time (SwiftUI's `.task(id:)` does exactly this).
///
/// **Breaks:** the banner comes and goes as for a programme. While a
/// commercial plays, a small badge in the corner says it's a break and when
/// the programme's back. The last commercial fades out into the "Up next"
/// card, which fills the last 15 seconds of every break; then the screen
/// fades to black and the programme fades in.
@MainActor @Observable
public final class WatchModel {
    /// An overlay over live TV.
    public enum Screen: Sendable { case channelList, guide, settings }

    public let surfer: ChannelSurfer
    public var player: ChannelPlayer { surfer.player }

    /// The banner was asked for (or a programme just started) and its timer hasn't run out.
    public private(set) var bannerVisible = true
    /// End time or time left, switched by showing the banner again while it's up.
    public private(set) var timeDisplay: BannerTimeDisplay = .endTime
    public private(set) var showingList = false
    public private(set) var showingGuide = false
    /// Settable, for a sheet that the viewer can also close by itself.
    public var showingSettings = false
    /// Black over everything but the guide and list, and how long its
    /// current change takes (fading in, or out). The sound fades with it, so
    /// the end of a commercial isn't heard over the black.
    public private(set) var curtain = Curtain(closed: false, fade: 0) {
        didSet {
            guard curtain != oldValue else { return }
            fadeSound(to: curtain.closed ? 0 : 1, over: curtain.fade)
        }
    }

    /// Goes up each time the viewer asks for the banner, to restart its timer.
    private var bannerRequests = 0
    /// Settings was opened from the guide, so closing it goes back there.
    private var settingsReturnsToGuide = false
    /// When the guide or list last opened or closed, for ignoring too-quick clicks.
    private var lastOverlayChange = Date.distantPast
    /// The break the banner is showing, worked out once per airing.
    @ObservationIgnored private var soundFade: Task<Void, Never>?
    @ObservationIgnored private var breakCache: (airing: Airing, span: DateInterval?, after: MediaItem?)?

    /// Opening or closing the guide, list or Settings within this long of the
    /// last change is ignored, so a double-click (or a held key repeating)
    /// can't open the guide and immediately select something in it.
    public static let clickGuard: TimeInterval = 0.5
    /// How long the banner stays up.
    public static let bannerTime: Duration = .seconds(6)
    /// The last commercial fading out, and the Up next card fading in.
    public static let quickFade: TimeInterval = 0.5
    public static let fadeToBlack: TimeInterval = 0.8
    /// Fully black for this long before the programme starts.
    public static let holdBlack: TimeInterval = 0.4
    public static let fadeIn: TimeInterval = 1.2
    /// The picture's fade out and back in when changing channel.
    public static let channelChangeFade: TimeInterval = 0.4

    public init(surfer: ChannelSurfer) {
        self.surfer = surfer
    }

    // MARK: - The screen appearing and going

    /// The watch screen is on: play, and apply any debug launch options.
    public func appeared(showsDiagnostics: Bool) {
        player.start()
        player.diagnosticsEnabled = showsDiagnostics
        #if DEBUG
        if DebugOptions.opensChannelList { show(.channelList) }
        if DebugOptions.opensGuide { show(.guide) }
        #endif
    }

    public func disappeared() {
        player.stop()
    }

    /// Only a real trip to the background stops playback. Becoming inactive
    /// (a system overlay) leaves the stream alone, and `start()` does nothing
    /// if it's already playing.
    public func appBecameActive() { player.start() }
    public func appWentToBackground() { player.stop() }

    // MARK: - Remote actions

    /// Does what a remote button is mapped to in `RemoteControls`.
    public func perform(_ action: RemoteAction) {
        switch action {
        case .channelUp: surfer.channelUp()
        case .channelDown: surfer.channelDown()
        case .showInfo: showInfo()
        case .hideInfo: hideInfo()
        case .hideInfoOrOpenGuide:
            if bannerCanBeHidden { hideInfo() } else { show(.guide) }
        case .pauseOrJumpToLive: player.togglePause()
        case .openChannelList: show(.channelList)
        case .openGuide: show(.guide)
        case .openSettings: show(.settings)
        case .close, .stepBack:
            showingSettings = false
            closeOverlays()
        }
    }

    /// A channel chosen in the list or the guide.
    public func select(channel number: Int) {
        guard !changedRecently else { return }
        surfer.tune(to: number)
        closeOverlays()
    }

    /// A digit typed on a keyboard.
    public func type(digit: Character) {
        surfer.type(digit: digit)
    }

    /// Settings has closed (by any route). True if focus should go back to
    /// live TV; false if the guide it was opened from is back instead.
    @discardableResult
    public func settingsClosed() -> Bool {
        guard settingsReturnsToGuide else { return true }
        settingsReturnsToGuide = false
        showingGuide = true
        return false
    }

    /// The channel list or guide is open and owns remote input.
    public var overlayOpen: Bool { showingList || showingGuide }

    /// Remote input for live TV is live: nothing is open over it.
    public var takesRemoteInput: Bool { !overlayOpen && !showingSettings }

    /// Opens one of the list, guide or Settings, closing whichever else is open.
    public func show(_ screen: Screen) {
        guard !changedRecently else { return }
        lastOverlayChange = .now
        settingsReturnsToGuide = screen == .settings && showingGuide
        showingList = screen == .channelList
        showingGuide = screen == .guide
        showingSettings = screen == .settings
    }

    private func closeOverlays() {
        lastOverlayChange = .now
        showingList = false
        showingGuide = false
    }

    private var changedRecently: Bool {
        Date.now.timeIntervalSince(lastOverlayChange) < Self.clickGuard
    }

    // MARK: - The banner

    /// The banner is on screen: asked for, surfing, or saying something
    /// (paused, buffering, tuning, between programmes).
    public var bannerIsShowing: Bool {
        bannerVisible || surfer.preview != nil || player.status != .playing || player.isBuffering
    }

    /// When this changes, restart `runBannerTimer()`: a new programme (not
    /// each clip in a break), a re-tune, or a request.
    public var bannerTrigger: BannerTrigger {
        BannerTrigger(airing: player.airing?.isFiller == true ? nil : player.airing,
                      tuneCount: player.tuneCount, requests: bannerRequests)
    }

    /// Shows the banner, then hides it after `bannerTime`. A restarted run
    /// (cancelled) leaves it alone: the new run decides.
    public func runBannerTimer() async {
        bannerVisible = true
        try? await Task.sleep(for: Self.bannerTime)
        guard !Task.isCancelled else { return }
        bannerVisible = false
    }

    /// Show the banner, or if it's already showing, switch between end time
    /// and time left (and keep it up).
    private func showInfo() {
        if bannerIsShowing { timeDisplay.toggle() }
        bannerRequests += 1
    }

    /// The banner is up only because it was asked for (or a programme just
    /// started), so hiding it would make it go. While paused, buffering,
    /// surfing or between programmes it stays: it's saying something.
    private var bannerCanBeHidden: Bool {
        bannerVisible && surfer.preview == nil && player.status == .playing && !player.isBuffering
    }

    private func hideInfo() {
        bannerVisible = false
    }

    /// What the banner says at `date`. While surfing, it previews the
    /// channel being moved to.
    public func banner(at date: Date) -> BannerContent {
        let schedule = surfer.displayedChannel
        let (breakSpan, afterBreak) = breakShown()
        // A programme is shown whole: for a film split by mid-roll breaks,
        // from its start to its end, not just the part playing.
        let playing = player.airing.map { $0.isFiller ? $0 : schedule.programme(at: $0.start) }
        let airing = surfer.preview.map { $0.programme(at: date) } ?? playing
        let hint = RemoteControls.hint(for: RemoteControls.watching)
        let diagnostics = player.diagnosticsEnabled && surfer.preview == nil
            ? [player.streamDescription, player.diagnostics].compactMap { $0 } : []
        guard let airing else {
            return BannerContent(channelNumber: schedule.channel.number, channelName: schedule.channel.name,
                                 programme: nil, hint: hint, diagnostics: diagnostics)
        }
        let span = (airing.isFiller && surfer.preview == nil ? breakSpan : nil)
            ?? DateInterval(start: airing.start, end: airing.isFiller ? airing.slotEnd : airing.end)
        let subtitle: String? = if airing.isFiller {
            afterBreak.map { "Back at \(Self.time(span.end)) with \($0.displayTitle)" } ?? "Back at \(Self.time(span.end))"
        } else {
            airing.item.displaySubtitle
        }
        let programme = BannerContent.Programme(
            title: airing.isFiller ? BreakText.title : airing.item.displayTitle,
            subtitle: subtitle,
            progress: Self.progress(of: span, at: date),
            started: Self.startedText(span, at: date),
            time: timeText(span, at: date),
            status: statusNote(at: date))
        return BannerContent(channelNumber: schedule.channel.number, channelName: schedule.channel.name,
                             programme: programme, hint: hint, diagnostics: diagnostics)
    }

    /// The whole break the playing commercial is in, and the programme
    /// after it, worked out once per airing: each clip is only a minute or so.
    private func breakShown() -> (DateInterval?, MediaItem?) {
        guard let airing = player.airing, airing.isFiller else { return (nil, nil) }
        if let cache = breakCache, cache.airing == airing { return (cache.span, cache.after) }
        let schedule = surfer.displayedChannel
        let span = schedule.commercialBreak(at: airing.start)
        let after = span.map { schedule.programme(at: $0.end).item }
        breakCache = (airing, span, after)
        return (span, after)
    }

    /// "5:00 PM · 17 min in".
    private static func startedText(_ span: DateInterval, at date: Date) -> String {
        let start = time(span.start)
        let elapsed = min(date, span.end).timeIntervalSince(span.start)
        guard elapsed >= 60 else { return start }
        return "\(start) · \(duration(elapsed)) in"
    }

    /// "Ends 6:59 PM", or "42 min left", depending on the viewer's choice.
    private func timeText(_ span: DateInterval, at date: Date) -> String {
        let remaining = span.end.timeIntervalSince(date)
        guard remaining > 0 else { return "Ended" }
        switch timeDisplay {
        case .endTime: return "Ends \(Self.time(span.end))"
        case .remaining: return remaining < 60 ? "Less than a minute left" : "\(Self.duration(remaining)) left"
        }
    }

    private static func progress(of span: DateInterval, at date: Date) -> Double {
        guard span.duration > 0 else { return 1 }
        return min(1, max(0, date.timeIntervalSince(span.start) / span.duration))
    }

    /// The note in the middle of the banner, if there's something to say.
    private func statusNote(at date: Date) -> String? {
        if surfer.preview != nil { return "Tuning in…" }
        switch player.status {
        case .tuning:
            return "Tuning in…"
        case .playing where player.isBuffering:
            return "Buffering…"
        case .startingSoon(let at) where at > date:
            return "Getting this ready · starts in \(Int(at.timeIntervalSince(date).rounded(.up))) s"
        case .startingSoon:
            return "Getting this ready…"   // waiting a little longer for a cushion
        case .betweenProgrammes(let until) where player.schedule.commercialBreak(at: until) == nil:
            // (Inside a break, "Back at" already says when the programme starts.)
            let resumes = player.schedule.tune(at: until).airing.mediaOffset > 0
            return "\(resumes ? "Back at" : "Next programme at") \(Self.time(until))"
        case .paused(let since):
            let ahead = Duration.seconds(date.timeIntervalSince(since)).formatted(.time(pattern: .minuteSecond))
            return "PAUSED · live is \(ahead) ahead · ▶︎ to jump to live"
        default:
            return nil
        }
    }

    // MARK: - Cards and the badge

    /// A commercial is playing: the corner badge says so when the banner's down.
    public var showsBreakBadge: Bool {
        !bannerIsShowing && player.status == .playing && player.airing?.isFiller == true && !overlayOpen
    }

    /// "Back at 9:30 PM", for the badge next to "Commercial break".
    public var breakBadgeBackAt: String? {
        player.airing.flatMap { player.schedule.commercialBreak(at: $0.start)?.end }.map { "Back at \(Self.time($0))" }
    }

    /// Blank between programmes (a gap with nothing to play), and while a
    /// head start buffers: no frame held on screen.
    public var hidesVideo: Bool {
        switch player.status {
        case .betweenProgrammes, .startingSoon: true
        default: false
        }
    }

    /// Changing channel: the picture fades out as soon as surfing starts
    /// (the old channel carries on until the surfer settles) and back in
    /// once the new channel plays, over `channelChangeFade` each way, rather
    /// than cutting to black while the new stream loads. The banner stays up.
    public var changingChannel: Bool {
        surfer.preview != nil || player.status == .tuning
    }

    /// The full-screen card for gaps and failures, if one is showing.
    public var statusCard: StatusCardContent? {
        guard surfer.preview == nil else { return nil }
        switch player.status {
        case .betweenProgrammes(let until):
            // Inside a break (a skipped commercial), the next programme is after the break.
            let start = player.schedule.commercialBreak(at: until)?.end ?? until
            let next = player.schedule.airings(from: start, to: start.addingTimeInterval(1)).first
            // A mid-roll break in a film: it's still on, and carries on after.
            let resumes = (next?.mediaOffset ?? 0) > 0
            return .upNext(heading: resumes ? "Now playing" : "Up next",
                           title: next?.item.displayTitle,
                           when: "\(resumes ? "Back at" : "Starts at") \(Self.time(start))")
        case .failed(let message, let retryAt):
            return .failed(message: message, retryAt: retryAt)
        default:
            return nil
        }
    }

    /// What's typed so far ("1_"), or a notice such as "No channel 9".
    public var numberEntryText: String? {
        if let notice = surfer.notice { return notice }
        guard !surfer.typedDigits.isEmpty else { return nil }
        return surfer.typedDigits + String(repeating: "_", count: max(0, surfer.navigator.maxDigits - surfer.typedDigits.count))
    }

    /// For Settings' diagnostics: what was found in the commercials library,
    /// and how many clips were skipped.
    public func commercialsDiagnostics(playsCommercials: Bool, libraryStatus: String?) -> String? {
        let off = playsCommercials ? nil : "Turned off: breaks are blank."
        let parts = [off, libraryStatus, player.skippedCommercialsNote].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    // MARK: - The curtain

    /// When this changes, restart `runCurtain()`.
    public var curtainTrigger: CurtainTrigger {
        CurtainTrigger(status: player.status, airing: player.airing)
    }

    /// The fades at the end of a break: the last commercial out to black,
    /// the Up next card in from black, the card out to black just before the
    /// programme, and the programme in from black once it plays.
    ///
    /// Each timed fade checks, as it fires, that the player is still where it
    /// was when the fade was planned. A clip can end a moment before its
    /// scheduled end; a fade planned for it must not then close the curtain
    /// over the Up next card, even if an earlier run is still waiting.
    public func runCurtain() async {
        switch player.status {
        case .playing:
            // Something to show: a programme (after a break) or a commercial.
            if curtain.closed { curtain = Curtain(closed: false, fade: Self.fadeIn) }
            // The break's last commercial, with the Up next card after it
            // (it stops short of the next programme): fade it out as it ends.
            guard let clip = player.airing, clip.isFiller, clip.slotEnd.timeIntervalSince(clip.end) > 1 else { return }
            try? await Task.sleep(for: .seconds(max(0, clip.end.timeIntervalSinceNow - Self.quickFade)))
            guard !Task.isCancelled, player.status == .playing, player.airing == clip else { return }
            curtain = Curtain(closed: true, fade: Self.quickFade)
        case .betweenProgrammes(let until) where !player.schedule.tune(at: until).airing.isFiller:
            // The Up next card fades in, then out to black just before the programme.
            if curtain.closed { curtain = Curtain(closed: false, fade: Self.quickFade) }
            let closeAt = until.addingTimeInterval(-(Self.fadeToBlack + Self.holdBlack))
            try? await Task.sleep(for: .seconds(max(0, closeAt.timeIntervalSinceNow)))
            guard !Task.isCancelled, player.status == .betweenProgrammes(until: until) else { return }
            curtain = Curtain(closed: true, fade: Self.fadeToBlack)
        case .tuning:
            break   // stays as it is until there's something to show
        default:
            if curtain.closed { curtain = Curtain(closed: false, fade: Self.fadeIn) }
        }
    }

    /// Ramps the player's volume to `target` over `seconds`, replacing any ramp under way.
    private func fadeSound(to target: Float, over seconds: TimeInterval) {
        soundFade?.cancel()
        let from = player.volume
        let steps = max(1, Int(seconds / 0.05))
        soundFade = Task { [player] in
            for step in 1...steps {
                if seconds > 0 { try? await Task.sleep(for: .seconds(seconds / Double(steps))) }
                guard !Task.isCancelled else { return }
                player.volume = from + (target - from) * Float(step) / Float(steps)
            }
        }
    }

    // MARK: - Formatting

    static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    /// "42 min" or "1 hr, 5 min".
    static func duration(_ seconds: TimeInterval) -> String {
        Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }
}

/// When it changes, the banner's timer restarts.
public struct BannerTrigger: Equatable, Sendable {
    let airing: Airing?
    let tuneCount: Int
    let requests: Int
}

/// When it changes, the curtain's fades are worked out again.
public struct CurtainTrigger: Equatable, Sendable {
    let status: ChannelPlayer.Status
    let airing: Airing?
}

/// Black over the picture, closed or open, and how long the change to this
/// state takes (closing eases in; opening eases out).
public struct Curtain: Equatable, Sendable {
    public let closed: Bool
    public let fade: TimeInterval
}

/// What the banner shows on the right of the progress bar.
public enum BannerTimeDisplay: Sendable {
    case endTime
    case remaining

    mutating func toggle() {
        self = self == .endTime ? .remaining : .endTime
    }
}

/// The words on the info banner.
public struct BannerContent: Sendable {
    public struct Programme: Sendable {
        /// The programme's title, or "Commercial break".
        public let title: String
        /// "S1 E7 · The Map", "1939", or in a break, "Back at 9:30 PM with …".
        public let subtitle: String?
        /// How far through, 0 to 1.
        public let progress: Double
        /// "9:00 PM · 17 min in".
        public let started: String
        /// "Ends 9:47 PM", or "42 min left".
        public let time: String
        /// "Buffering…", "PAUSED · …" and so on, for the middle of the bar.
        public let status: String?
    }

    public let channelNumber: Int
    public let channelName: String
    public let programme: Programme?
    /// Which remote button does what, from `RemoteControls.watching`.
    public let hint: String
    /// With "Show playback diagnostics" on: the stream, and what the player's doing.
    public let diagnostics: [String]
}

/// The full-screen card over a gap or a failure.
public enum StatusCardContent: Sendable, Equatable {
    /// "Up next" (or "Now playing" in a film's mid-roll), the title, and "Starts at …".
    case upNext(heading: String, title: String?, when: String)
    /// What went wrong, and when it'll try again.
    case failed(message: String, retryAt: Date)
}
