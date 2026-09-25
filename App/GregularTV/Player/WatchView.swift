import GregularCore
import GregularScreens
import SwiftUI

/// Full-screen live TV on Apple TV, drawing a `WatchModel`: the picture, the
/// info banner, the corner badge, the Up next card, the curtain, and the
/// channel list, guide and Settings over it. What happens when is decided
/// in `WatchModel` (shared with any other version of the app); this view
/// only draws it and connects the Siri Remote.
///
/// **Remote controls** are set in one place, `RemoteControls` (in
/// GregularScreens): a table per screen of which button does what. As
/// shipped, while watching:
/// - **Click left / right** (the edge of the pad): channel down / up (the
///   banner previews each channel as you go).
/// - **Slide left:** channel list (slide right closes it).
/// - **Light touch** (a click touches the pad too): show the info banner.
///   Again while it's showing: switch between the end time and the time left.
/// - **Menu (or Back ‹):** hide the banner if it's up; otherwise the
///   programme guide. In the guide, Menu first moves up to its Settings
///   button, then goes back to the programme.
/// - **Click and hold:** Settings (quality, schedule code, diagnostics, sign out).
/// - **Play/Pause:** pause, then press again to jump back to live.
/// - **Digits** (keyboard only; the Siri Remote has none): type a channel number.
struct WatchView: View {
    let scheduleCode: ScheduleCode
    let showsDiagnostics: Bool
    let playsCommercials: Bool
    let commercialsStatus: String?
    let onQualityChange: (StreamingQuality) -> Void
    let onScheduleCodeChange: (ScheduleCode) -> Void
    let onShowsDiagnosticsChange: (Bool) -> Void
    let onPlaysCommercialsChange: (Bool) -> Void
    let onSignOut: () -> Void

    @State private var model: WatchModel
    @Environment(\.scenePhase) private var scenePhase
    /// Focus is on the live-TV input layer (not in the list or guide).
    @FocusState private var watchingHasFocus: Bool

    init(surfer: ChannelSurfer, scheduleCode: ScheduleCode, showsDiagnostics: Bool, playsCommercials: Bool,
         commercialsStatus: String?, onQualityChange: @escaping (StreamingQuality) -> Void,
         onScheduleCodeChange: @escaping (ScheduleCode) -> Void, onShowsDiagnosticsChange: @escaping (Bool) -> Void,
         onPlaysCommercialsChange: @escaping (Bool) -> Void, onSignOut: @escaping () -> Void) {
        _model = State(initialValue: WatchModel(surfer: surfer))
        self.scheduleCode = scheduleCode
        self.showsDiagnostics = showsDiagnostics
        self.playsCommercials = playsCommercials
        self.commercialsStatus = commercialsStatus
        self.onQualityChange = onQualityChange
        self.onScheduleCodeChange = onScheduleCodeChange
        self.onShowsDiagnosticsChange = onShowsDiagnosticsChange
        self.onPlaysCommercialsChange = onPlaysCommercialsChange
        self.onSignOut = onSignOut
    }

    private var player: ChannelPlayer { model.player }
    private var surfer: ChannelSurfer { model.surfer }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.ignoresSafeArea()
            // Two stacked surfaces; the active deck's is on top. The one
            // behind buffers the programme after a commercial break.
            ZStack {
                ForEach(player.decks.indices, id: \.self) { index in
                    if let deck = player.decks[index] as? AVPlayerDeck {
                        VideoSurface(player: deck.player)
                            .zIndex(index == player.activeIndex ? 1 : 0)
                    }
                }
            }
            .ignoresSafeArea()
            .opacity(model.hidesVideo ? 0 : 1)
            .opacity(model.changingChannel ? 0 : 1)
            .animation(.easeInOut(duration: WatchModel.channelChangeFade), value: model.changingChannel)
            liveTVInput
            // Edge clicks, swipes and light touches, told apart (SwiftUI can't).
            RemoteGestures(map: RemoteControls.watching, isEnabled: model.takesRemoteInput, perform: model.perform)
                .frame(width: 0, height: 0)

            if let card = model.statusCard {
                StatusCard(content: card)
            }
            if model.bannerIsShowing {
                ChannelBanner(model: model)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if model.showsBreakBadge {
                BreakBadge(backAt: model.breakBadgeBackAt)
                    .transition(.opacity)
            }
            if let text = model.numberEntryText {
                NumberEntryOverlay(text: text, isNotice: surfer.notice != nil)
            }
            Color.black
                .ignoresSafeArea()
                .opacity(model.curtain.closed ? 1 : 0)
                .animation(model.curtain.closed ? .easeIn(duration: model.curtain.fade)
                                                : .easeOut(duration: model.curtain.fade),
                           value: model.curtain)
                .allowsHitTesting(false)
            if model.showingList {
                HStack {
                    ChannelListView(channels: surfer.channels,
                                    currentNumber: player.schedule.channel.number,
                                    onSelect: model.select(channel:),
                                    onRemote: model.perform)
                    Spacer()
                }
                .ignoresSafeArea()
                .transition(.move(edge: .leading))
            }
            if model.showingGuide {
                GuideView(channels: surfer.channels,
                          currentNumber: player.schedule.channel.number,
                          onSelect: model.select(channel:),
                          onRemote: model.perform)
                    .ignoresSafeArea()
                    .transition(.opacity)
            }
        }
        .animation(.default, value: model.bannerIsShowing)
        .animation(.default, value: model.showsBreakBadge)
        .animation(.default, value: model.showingList)
        .animation(.default, value: model.showingGuide)
        .sheet(isPresented: $model.showingSettings) {
            SettingsView(current: player.quality,
                         streamDescription: player.streamDescription,
                         programmeTitle: player.fixableProgramme?.item.displayTitle,
                         programmeFix: player.programmeFix,
                         scheduleCode: scheduleCode,
                         showsDiagnostics: showsDiagnostics,
                         playsCommercials: playsCommercials,
                         commercialsStatus: model.commercialsDiagnostics(playsCommercials: playsCommercials,
                                                                         libraryStatus: commercialsStatus),
                         onSelect: onQualityChange,
                         onProgrammeFix: { player.setProgrammeFix($0) },
                         onScheduleCodeChange: onScheduleCodeChange,
                         onShowsDiagnosticsChange: onShowsDiagnosticsChange,
                         onPlaysCommercialsChange: onPlaysCommercialsChange,
                         onSignOut: onSignOut,
                         onRemote: model.perform)
        }
        .onAppear {
            model.appeared(showsDiagnostics: showsDiagnostics)
            UIApplication.shared.isIdleTimerDisabled = true
            watchingHasFocus = true
        }
        .onDisappear {
            model.disappeared()
            UIApplication.shared.isIdleTimerDisabled = false
        }
        // Focus goes back to live TV once the input layer can take it again.
        // Setting it in the same update that closes an overlay could fail and
        // leave nothing focused.
        .onChange(of: model.overlayOpen) { _, open in
            if !open { watchingHasFocus = true }
        }
        .onChange(of: model.showingSettings) { _, showing in
            if !showing, model.settingsClosed() { watchingHasFocus = true }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: model.appBecameActive()
            case .background: model.appWentToBackground()
            default: break
            }
        }
        .task(id: model.curtainTrigger) { await model.runCurtain() }
        .task(id: model.bannerTrigger) { await model.runBannerTimer() }
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
            .focusable(!model.overlayOpen)
            .focused($watchingHasFocus)
            .focusEffectDisabled()
            // Before the remote table's handlers, as it was before they moved into it.
            .onKeyPress(characters: .decimalDigits) { press in
                press.characters.forEach(model.type(digit:))
                return .handled
            }
            .remoteControls(RemoteControls.watching, takesClicks: true, takesArrows: false, perform: model.perform)
    }
}

/// The lower-third: channel, programme, progress, and status notes. While
/// surfing, it previews the channel you're moving to.
private struct ChannelBanner: View {
    let model: WatchModel

    /// The channel column's width, the same on every channel.
    static let channelWidth: CGFloat = 300

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let banner = model.banner(at: context.date)
            let programme = banner.programme
            // Every part keeps its place and size whatever the channel or
            // programme: long text is cut short, and a missing line keeps its
            // space, so flicking through channels doesn't reshape the banner.
            HStack(alignment: .top, spacing: 32) {
                VStack(alignment: .leading) {
                    Text(banner.channelNumber, format: .number)
                        .font(.system(size: 64, weight: .bold, design: .rounded))
                    Text(banner.channelName).font(.headline).foregroundStyle(.secondary)
                }
                .lineLimit(1)
                .frame(width: Self.channelWidth, alignment: .leading)
                VStack(alignment: .leading, spacing: 10) {
                    Text(programme?.title ?? " ").font(.title2).bold()
                    Text(programme?.subtitle ?? " ").font(.headline).foregroundStyle(.secondary)
                    PlayheadBar(fraction: programme?.progress ?? 0)
                        .opacity(programme == nil ? 0 : 1)
                    // The status note is centred on the bar, whatever the
                    // widths either side, so switching end time / time left
                    // doesn't nudge it.
                    HStack(alignment: .firstTextBaseline) {
                        Text(programme?.started ?? " ")
                        Spacer()
                        Text(programme?.time ?? " ").monospacedDigit()
                    }
                    .overlay {
                        if let status = programme?.status {
                            Text(status).foregroundStyle(.yellow)
                        }
                    }
                    .font(.caption).foregroundStyle(.secondary)
                    Text(banner.hint)
                        .font(.caption2).foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    if !banner.diagnostics.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(banner.diagnostics, id: \.self) { Text($0) }
                        }
                        .font(.caption2.monospaced()).foregroundStyle(.orange)
                    }
                }
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)   // the bar runs up to the clock
                // The current time, like the clock in Apple's own players, in
                // a slot as wide as the widest time.
                ZStack(alignment: .trailing) {
                    Text(Self.widestTime, style: .time).hidden()
                    Text(context.date, style: .time)
                }
                .font(.title3.monospacedDigit()).bold()
                .foregroundStyle(.secondary)
            }
            .padding(40)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
            .padding(60)
        }
    }

    /// 10:58 PM (or 22:58): as many digits as a time can have.
    private static let widestTime = Calendar.current.date(bySettingHour: 22, minute: 58, second: 0, of: .now) ?? .now
}

/// While a commercial plays and the banner's down: a small badge in the top
/// corner, "Commercial break · Back at 9:30 PM", so it's clear the
/// programme is over without covering the picture.
private struct BreakBadge: View {
    let backAt: String?

    var body: some View {
        VStack {
            HStack(spacing: 10) {
                BreakStyle.label
                if let backAt { Text("· \(backAt)") }
            }
            .font(.callout).foregroundStyle(.secondary)
            .padding(.horizontal, 24).padding(.vertical, 12)
            .background(.ultraThinMaterial, in: Capsule())
            .frame(maxWidth: .infinity, alignment: .leading)
            Spacer()
        }
        // Tucked into the corner, outside the usual safe margins: it's small
        // and only there to say it's a break.
        .padding(.leading, 40)
        .padding(.top, 28)
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

/// Top-right digits while typing a channel number, like "1_", or a notice.
private struct NumberEntryOverlay: View {
    let text: String
    let isNotice: Bool

    var body: some View {
        VStack {
            HStack {
                Spacer()
                Text(text)
                    .font(.system(size: isNotice ? 48 : 96, weight: .bold, design: .rounded).monospacedDigit())
                    .padding(.horizontal, 40).padding(.vertical, 20)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
            }
            Spacer()
        }
        .padding(60)
    }
}

/// Full-screen card for gaps and playback failures.
private struct StatusCard: View {
    let content: StatusCardContent

    var body: some View {
        VStack(spacing: 24) {
            switch content {
            case .upNext(let heading, let title, let when):
                Text(heading).font(.title3).foregroundStyle(.secondary)
                if let title { Text(title).font(.largeTitle).bold() }
                Text(when)
            case .failed(let message, let retryAt):
                Image(systemName: "exclamationmark.triangle").font(.system(size: 80))
                Text(message).font(.title3).multilineTextAlignment(.center)
                Text("Trying again \(retryAt, style: .relative)…")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(80)
        // Sit in the upper part of the screen, clear of the banner.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 160)
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
