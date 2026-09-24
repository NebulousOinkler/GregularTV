import GregularTVCore
import SwiftUI

/// Full-screen live TV with the info banner, channel list and settings.
///
/// Remote controls:
/// - **Up/down:** channel up/down (the banner previews each channel as you go).
/// - **Left:** channel list. **Menu** closes it.
/// - **Right, or a light tap on the touch surface:** show the info banner. Again
///   while it's showing: switch between the end time and the time left.
///   During a commercial break the banner stays up the whole time.
/// - **Click (Select):** programme guide. **Menu** closes it.
/// - **Click and hold:** Settings (quality, schedule code, diagnostics, sign out).
///   Also from the guide: Play/Pause, or Up from its top row.
///
/// Clicks within half a second of the guide or list opening or closing are
/// ignored, so a double-click (or a held key repeating) can't open the guide
/// and immediately select something in it.
/// - **Play/Pause:** pause, then press again to jump back to live.
/// - **Digits** (keyboard only; the Siri Remote has none): type a channel number.
struct WatchView: View {
    let surfer: ChannelSurfer
    let scheduleCode: ScheduleCode
    let showsDiagnostics: Bool
    let playsCommercials: Bool
    let commercialsStatus: String?
    let onQualityChange: (StreamingQuality) -> Void
    let onScheduleCodeChange: (ScheduleCode) -> Void
    let onShowsDiagnosticsChange: (Bool) -> Void
    let onPlaysCommercialsChange: (Bool) -> Void
    let onSignOut: () -> Void

    private var player: ChannelPlayer { surfer.player }

    @Environment(\.scenePhase) private var scenePhase
    @State private var bannerVisible = true
    /// Goes up each time the viewer asks for the banner, to restart its timer.
    @State private var bannerRequests = 0
    /// End time or time left, switched by pressing Right or tapping again. Kept while the app runs.
    @State private var timeDisplay: BannerTimeDisplay = .endTime
    @State private var showingSettings = false
    @State private var showingList = false
    @State private var showingGuide = false
    /// When the guide or list last opened or closed, for ignoring too-quick clicks.
    @State private var lastOverlayChange = Date.distantPast
    static let clickGuard: TimeInterval = 0.5
    /// Focus is on the live-TV input layer (not in the list or guide).
    @FocusState private var watchingHasFocus: Bool

    /// The channel list or guide is open and owns remote input.
    private var overlayOpen: Bool { showingList || showingGuide }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.ignoresSafeArea()
            // Two stacked surfaces; the active player's is on top. The one
            // behind buffers the programme after a commercial break.
            ZStack {
                ForEach(player.players.indices, id: \.self) { index in
                    VideoSurface(player: player.players[index])
                        .zIndex(index == player.activeIndex ? 1 : 0)
                }
            }
            .ignoresSafeArea()
            // Blank between programmes (a gap with nothing to play), and
            // while a head start buffers, not a frame held on screen.
            .opacity(hidesVideo ? 0 : 1)
            liveTVInput
            RemoteSurfaceTap(isEnabled: !overlayOpen && !showingSettings, action: showInfo)
                .frame(width: 0, height: 0)

            if showsCard {
                StatusCard(player: player)
            }
            if bannerIsShowing {
                ChannelBanner(surfer: surfer, timeDisplay: timeDisplay)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if !surfer.typedDigits.isEmpty || surfer.notice != nil {
                NumberEntryOverlay(digits: surfer.typedDigits, maxDigits: surfer.navigator.maxDigits,
                                   notice: surfer.notice)
            }
            if showingList {
                HStack {
                    ChannelListView(channels: surfer.channels,
                                    currentNumber: player.schedule.channel.number,
                                    onSelect: { number in
                                        guard !changedRecently else { return }
                                        surfer.tune(to: number)
                                        closeOverlays()
                                    },
                                    onClose: closeOverlays)
                    Spacer()
                }
                .ignoresSafeArea()
                .transition(.move(edge: .leading))
            }
            if showingGuide {
                GuideView(channels: surfer.channels,
                          currentNumber: player.schedule.channel.number,
                          onSelect: { number in
                              guard !changedRecently else { return }
                              surfer.tune(to: number)
                              closeOverlays()
                          },
                          onOpenSettings: {
                              closeOverlays()
                              showingSettings = true
                          },
                          onClose: closeOverlays)
                    .ignoresSafeArea()
                    .transition(.opacity)
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(current: player.quality,
                         streamDescription: player.streamDescription,
                         programmeTitle: player.fixableProgramme?.item.displayTitle,
                         programmeFix: player.programmeFix,
                         scheduleCode: scheduleCode,
                         showsDiagnostics: showsDiagnostics,
                         playsCommercials: playsCommercials,
                         commercialsStatus: commercialsDiagnostics,
                         onSelect: onQualityChange,
                         onProgrammeFix: { player.setProgrammeFix($0) },
                         onScheduleCodeChange: onScheduleCodeChange,
                         onShowsDiagnosticsChange: onShowsDiagnosticsChange,
                         onPlaysCommercialsChange: onPlaysCommercialsChange,
                         onSignOut: onSignOut)
        }
        .onAppear {
            player.start()
            UIApplication.shared.isIdleTimerDisabled = true
            watchingHasFocus = true
            player.diagnosticsEnabled = showsDiagnostics
            #if DEBUG
            if DebugOptions.opensChannelList { openList() }
            #endif
        }
        .onDisappear {
            player.stop()
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .onChange(of: overlayOpen) { _, open in
            if !open { watchingHasFocus = true }
        }
        .onChange(of: showingSettings) { _, showing in
            if !showing { watchingHasFocus = true }
        }
        // Only a real trip to the background stops playback. Becoming inactive
        // (Control Center, a notification) leaves the stream alone, and
        // `start()` does nothing if it's already playing.
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: player.start()
            case .background: player.stop()
            default: break
            }
        }
        // Show the banner for a few seconds whenever the programme changes or we
        // re-tune. Not for each clip in a commercial break.
        .task(id: BannerTrigger(airing: player.airing?.isFiller == true ? nil : player.airing,
                                tuneCount: player.tuneCount, requests: bannerRequests)) {
            withAnimation { bannerVisible = true }
            try? await Task.sleep(for: .seconds(6))
            withAnimation { bannerVisible = false }
        }
    }

    /// An invisible full-screen layer that owns the remote while watching.
    ///
    /// It sits *behind* the channel list and guide rather than wrapping them,
    /// so their buttons get arrows, clicks and Menu without them also
    /// changing channel or reopening an overlay. It stops being focusable while
    /// an overlay is open, so focus can't wander back to it.
    private var liveTVInput: some View {
        Color.clear
            .contentShape(Rectangle())
            .ignoresSafeArea()
            .focusable(!overlayOpen)
            .focused($watchingHasFocus)
            .focusEffectDisabled()
            .onMoveCommand { direction in
                switch direction {
                case .up: surfer.channelUp()
                case .down: surfer.channelDown()
                case .left: openList()
                case .right: showInfo()
                default: break
                }
            }
            .onKeyPress(characters: .decimalDigits) { press in
                press.characters.forEach(surfer.type(digit:))
                return .handled
            }
            .onPlayPauseCommand { player.togglePause() }
            // Hold: Settings. A quick click: the guide.
            .onLongPressGesture(minimumDuration: 0.6) { openSettings() }
            .onTapGesture { openGuide() }
        // No Menu handler here: while watching, Menu leaves the app as usual.
    }

    private var changedRecently: Bool {
        Date.now.timeIntervalSince(lastOverlayChange) < Self.clickGuard
    }

    private func openGuide() {
        guard !overlayOpen, !showingSettings, !changedRecently else { return }
        lastOverlayChange = .now
        withAnimation { showingGuide = true }
    }

    private func openList() {
        guard !overlayOpen, !showingSettings, !changedRecently else { return }
        lastOverlayChange = .now
        withAnimation { showingList = true }
    }

    private func openSettings() {
        guard !overlayOpen, !showingSettings, !changedRecently else { return }
        showingSettings = true
    }

    /// Focus goes back to live TV from `onChange(of: overlayOpen)`, once the
    /// input layer can take focus again. Setting it here, in the same update
    /// that closes the overlay, could fail and leave nothing focused.
    private func closeOverlays() {
        lastOverlayChange = .now
        withAnimation {
            showingList = false
            showingGuide = false
        }
    }

    private struct BannerTrigger: Equatable {
        let airing: Airing?
        let tuneCount: Int
        let requests: Int
    }

    /// Always up during a commercial break, so it's clear it's a break and
    /// when the next programme starts.
    private var bannerIsShowing: Bool {
        bannerVisible || surfer.preview != nil || player.status != .playing || player.isBuffering
            || player.airing?.isFiller == true
    }

    /// Right or a touch-surface tap: show the banner, or if it's already
    /// showing, switch between end time and time left (and keep it up).
    private func showInfo() {
        if bannerIsShowing { timeDisplay.toggle() }
        bannerRequests += 1
    }

    /// What was found in the commercials library, and how many clips were skipped.
    private var commercialsDiagnostics: String? {
        let off = playsCommercials ? nil : "Turned off: breaks are blank."
        let parts = [off, commercialsStatus, player.skippedCommercialsNote].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    private var hidesVideo: Bool {
        switch player.status {
        case .betweenProgrammes, .startingSoon: true
        default: false
        }
    }

    private var showsCard: Bool {
        guard surfer.preview == nil else { return false }
        switch player.status {
        case .betweenProgrammes, .failed: return true
        default: return false
        }
    }
}

/// The lower-third: channel, programme, progress, and status notes. While
/// surfing, it previews the channel you're moving to.
private struct ChannelBanner: View {
    let surfer: ChannelSurfer
    let timeDisplay: BannerTimeDisplay

    private var player: ChannelPlayer { surfer.player }

    var body: some View {
        // Worked out once per airing, not every second: during a break the
        // banner covers the whole break, since each clip is only a minute or so.
        let breakSpan = player.airing.flatMap { $0.isFiller ? surfer.displayedChannel.commercialBreak(at: $0.start) : nil }
        let afterBreak = breakSpan.map { surfer.displayedChannel.programme(at: $0.end).item }
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let schedule = surfer.displayedChannel
            let airing = surfer.preview.map { $0.programme(at: context.date) } ?? player.airing
            HStack(alignment: .top, spacing: 32) {
                VStack(alignment: .leading) {
                    Text(schedule.channel.number, format: .number)
                        .font(.system(size: 64, weight: .bold, design: .rounded))
                    Text(schedule.channel.name).font(.headline).foregroundStyle(.secondary)
                }
                if let airing {
                    let span = (airing.isFiller && surfer.preview == nil ? breakSpan : nil)
                        ?? DateInterval(start: airing.start, end: airing.isFiller ? airing.slotEnd : airing.end)
                    VStack(alignment: .leading, spacing: 10) {
                        Text(airing.isFiller ? "Commercial break" : airing.item.displayTitle)
                            .font(.title2).bold().lineLimit(1)
                        if airing.isFiller {
                            let backAt = "Back at \(span.end.formatted(date: .omitted, time: .shortened))"
                            Text(afterBreak.map { "\(backAt) with \($0.displayTitle)" } ?? backAt)
                                .font(.headline).foregroundStyle(.secondary).lineLimit(1)
                        } else if let subtitle = airing.item.displaySubtitle {
                            Text(subtitle).font(.headline).foregroundStyle(.secondary).lineLimit(1)
                        }
                        PlayheadBar(fraction: progress(of: span, at: context.date))
                        HStack(alignment: .firstTextBaseline) {
                            Text(startedText(span, at: context.date))
                            Spacer()
                            statusNote(at: context.date).foregroundStyle(.yellow)
                            Spacer()
                            Text(timeText(span, at: context.date)).monospacedDigit()
                        }
                        .font(.caption).foregroundStyle(.secondary)
                        Text("▲▼ channels · ◀ channel list · ▶ or tap: info, end time / time left · click: guide · hold click: settings")
                            .font(.caption2).foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        if player.diagnosticsEnabled, surfer.preview == nil {
                            VStack(alignment: .leading, spacing: 2) {
                                if let stream = player.streamDescription { Text(stream) }
                                if let diagnostics = player.diagnostics { Text(diagnostics.text) }
                            }
                            .font(.caption2.monospaced()).foregroundStyle(.orange)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)   // the bar runs up to the clock
                }
                // The current time, like the clock in Apple's own players.
                Text(context.date, style: .time)
                    .font(.title3.monospacedDigit()).bold()
                    .foregroundStyle(.secondary)
            }
            .padding(40)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
            .padding(60)
        }
    }

    /// "5:00 PM · 17 min in".
    private func startedText(_ span: DateInterval, at date: Date) -> String {
        let start = span.start.formatted(date: .omitted, time: .shortened)
        let elapsed = min(date, span.end).timeIntervalSince(span.start)
        guard elapsed >= 60 else { return start }
        return "\(start) · \(Self.duration(elapsed)) in"
    }

    /// "Ends 6:59 PM", or "42 min left", depending on the viewer's choice.
    private func timeText(_ span: DateInterval, at date: Date) -> String {
        let remaining = span.end.timeIntervalSince(date)
        guard remaining > 0 else { return "Ended" }
        switch timeDisplay {
        case .endTime: return "Ends \(span.end.formatted(date: .omitted, time: .shortened))"
        case .remaining: return remaining < 60 ? "Less than a minute left" : "\(Self.duration(remaining)) left"
        }
    }

    /// "42 min" or "1 hr, 5 min".
    private static func duration(_ seconds: TimeInterval) -> String {
        Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }

    private func progress(of span: DateInterval, at date: Date) -> Double {
        guard span.duration > 0 else { return 1 }
        return min(1, max(0, date.timeIntervalSince(span.start) / span.duration))
    }

    @ViewBuilder
    private func statusNote(at date: Date) -> some View {
        if surfer.preview != nil {
            Text("Tuning in…")
        } else {
            switch player.status {
            case .tuning:
                Text("Tuning in…")
            case .playing where player.isBuffering:
                Text("Buffering…")
            case .startingSoon(let at) where at > date:
                Text("Getting this ready · starts in \(Int(at.timeIntervalSince(date).rounded(.up))) s")
            case .startingSoon:
                Text("Getting this ready…")   // waiting a little longer for a cushion
            case .betweenProgrammes(let until) where player.schedule.commercialBreak(at: until) == nil:
                // (Inside a break, "Back at" already says when the programme starts.)
                Text("Next programme at \(until.formatted(date: .omitted, time: .shortened))")
            case .paused(let since):
                Text("PAUSED · live is \(Duration.seconds(date.timeIntervalSince(since)).formatted(.time(pattern: .minuteSecond))) ahead · ▶︎ to jump to live")
            default:
                EmptyView()
            }
        }
    }
}

/// Top-right digits while typing a channel number, like "1_".
private struct NumberEntryOverlay: View {
    let digits: String
    let maxDigits: Int
    let notice: String?

    var body: some View {
        VStack {
            HStack {
                Spacer()
                Text(notice ?? digits + String(repeating: "_", count: max(0, maxDigits - digits.count)))
                    .font(.system(size: notice == nil ? 96 : 48, weight: .bold, design: .rounded).monospacedDigit())
                    .padding(.horizontal, 40).padding(.vertical, 20)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
            }
            Spacer()
        }
        .padding(60)
    }
}

/// Full-screen card for padding gaps and playback failures.
private struct StatusCard: View {
    let player: ChannelPlayer

    var body: some View {
        VStack(spacing: 24) {
            switch player.status {
            case .betweenProgrammes(let until):
                // Inside a break (a skipped commercial), the next programme is after the break.
                let start = player.schedule.commercialBreak(at: until)?.end ?? until
                Text("Up next").font(.title3).foregroundStyle(.secondary)
                if let next = player.schedule.airings(from: start, to: start.addingTimeInterval(1)).first {
                    Text(next.item.displayTitle).font(.largeTitle).bold()
                }
                Text("Starts at \(start.formatted(date: .omitted, time: .shortened))")
            case .failed(let message, let retryAt):
                Image(systemName: "exclamationmark.triangle").font(.system(size: 80))
                Text(message).font(.title3).multilineTextAlignment(.center)
                Text("Trying again \(retryAt, style: .relative)…")
                    .foregroundStyle(.secondary)
            default:
                EmptyView()
            }
        }
        .padding(80)
        // Sit in the upper part of the screen, clear of the banner.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 160)
    }
}

/// What the banner shows on the right of the progress bar.
enum BannerTimeDisplay {
    case endTime
    case remaining

    mutating func toggle() {
        self = self == .endTime ? .remaining : .endTime
    }
}

/// A progress bar with a dot at the current point.
private struct PlayheadBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { geometry in
            let x = geometry.size.width * fraction
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.25))
                Capsule().fill(.white).frame(width: max(x, 6))
                Circle().fill(.white)
                    .frame(width: 18, height: 18)
                    .shadow(radius: 3)
                    .offset(x: min(max(x - 9, 0), geometry.size.width - 18))
            }
        }
        .frame(height: 18)
        .padding(.vertical, 4)
    }
}
