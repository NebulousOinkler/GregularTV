import Foundation
import GregularCore
import GregularScreens
import JavaScriptKit

/// Live TV, drawing a `WatchModel`: the picture, what's on (the banner) with
/// the controls, the corner badge, the Up next and station cards, the
/// curtain, and the channel list, guide and Settings over it. What happens
/// when is decided in `WatchModel` (shared with Apple TV); this only draws
/// it and connects touch, mouse and keyboard (`KeyboardControls`, through
/// the same `RemoteControls` tables).
///
/// On a phone held upright the picture sits at the top, what's on and the
/// controls under it, and every channel's now and next under that. In
/// landscape, and on larger screens, the picture fills the window and what's
/// on is a card over it, shown when the model says (tuning, surfing, info)
/// or when the controls are brought up with a tap or the mouse (`app.css`).
@MainActor final class WatchScreen: KeyTarget {
    let surfer: ChannelSurfer
    let element = El("div", "watch")
    private let app: AppModel
    private let model: WatchModel
    private var player: ChannelPlayer { model.player }

    private let stage = El("div", "stage")
    private let decks = El("div", "decks")
    private let cards = El("div", "cards")
    private let dim = El("div", "cover-dim")
    private let badge = El("div", "break-badge")
    private let numberEntry = El("div", "number-entry").attribute("aria-live", "assertive")
    private let curtain = El("div", "curtain")
    private let stageBar = El("div", "stage-bar")
    private let soundNote: El
    private let fullScreen: El
    private let now: NowPanel
    private let lineup = El("section", "lineup").attribute("aria-label", "All channels")
    private let lineupTitle = El("h2", "section-title", text: "On now")
    private let lineupRows: ChannelRows
    private let overlay = El("div", "overlay")
    /// What screen readers hear when the channel or programme changes.
    private let announcer = El("div", "sr-only").attribute("role", "status").attribute("aria-live", "polite")
    private var announced = ""

    private let clock = Clock(every: 1)
    private let lineupClock = Clock(every: 30)
    private var redraws: [Redraw] = []
    private let bannerTimer = TaskSlot<BannerTrigger>()
    private let curtainTimer = TaskSlot<CurtainTrigger>()
    private let stationCardTimer = TaskSlot<CurtainTrigger>()
    private var stationCard: StationCard?
    private var openPanel: (any Page)?
    private var openPanelKey = ""
    private var wasShowingSettings = false
    private let wakeLock = WakeLock()
    private var hiding: Task<Void, Never>?
    private var gesture: (x: Double, y: Double, mouse: Bool)?

    /// The main page is over it: the channel plays on, dimmed, and the
    /// keyboard is the main page's.
    var isCovered = false {
        didSet {
            guard isCovered != oldValue else { return }
            dim.hidden = !isCovered
            element.classed("covered", isCovered)
            element.inert = isCovered
            if isCovered {
                Keys.release(self)
                wakeLock.release()
            } else {
                Keys.take(self)
                wakeLock.request()
                model.returnedFromMainPage()
            }
        }
    }

    init(surfer: ChannelSurfer, app: AppModel) {
        self.surfer = surfer
        self.app = app
        let model = WatchModel(surfer: surfer, buttonNames: KeyboardControls.names)
        self.model = model
        // Escape from the guide's bar: the app shows the main page over this channel.
        model.onOpenMainPage = { [weak app] in app?.showMainPage() }
        now = NowPanel { action in model.perform(action) }
        soundNote = El.button("Tap for sound", icon: .sound, "sound-note") { SoundUnlock.unlock() }
        fullScreen = El.button("Full screen", icon: .fullScreen, "icon-button", labelHidden: true) { FullScreen.toggle() }
        fullScreen.hidden = !FullScreen.isAvailable
        lineupRows = ChannelRows(channels: surfer.channels) { number in model.select(channel: number) }

        stageBar.append(
            El("div", "group", [El.button("All servers", icon: .back, "icon-button", labelHidden: true) { model.perform(.openMainPage) }]),
            El("div", "group", [fullScreen]))
        dim.hidden = true
        for case let deck as VideoDeck in player.decks { decks.append(deck.element) }
        stage.append(decks, cards, badge, numberEntry, stageBar, soundNote, curtain, dim)
        lineup.append(lineupTitle)
        for (row, _) in lineupRows.rows { lineup.append(row) }
        element.append(stage, now.element, lineup, overlay, announcer)

        connectPointer()
        redraws = [
            Redraw { [weak self] in self?.drawPicture() },
            Redraw { [weak self] in self?.drawCards() },
            Redraw { [weak self] in self?.drawNow() },
            Redraw { [weak self] in self?.drawCurtain() },
            Redraw { [weak self] in self?.drawPanels() },
            Redraw { [weak self] in self?.drawTimers() },
            Redraw { [weak self] in self?.drawLineup() },
        ]
        model.appeared(showsDiagnostics: app.showsDiagnostics)
        Keys.take(self)
        wakeLock.request()
        FullScreen.onChange = { [weak self] in self?.drawFullScreen() }
    }

    func close() {
        redraws.forEach { $0.stop() }
        [bannerTimer.cancel, curtainTimer.cancel, stationCardTimer.cancel].forEach { $0() }
        clock.stop()
        lineupClock.stop()
        hiding?.cancel()
        stationCard?.close()
        openPanel?.close()
        model.disappeared()
        wakeLock.release()
        Keys.release(self)
    }

    // MARK: The keyboard

    func press(_ button: RemoteButton) -> Bool {
        guard model.takesRemoteInput else { return false }
        // Enter works a control as usual once one has focus.
        if button == .click, let focused = DOM.focused, focused != DOM.document.body.object { return false }
        guard let action = RemoteControls.watching[button] else { return false }
        model.perform(action)
        return true
    }

    func type(digit: Character) -> Bool {
        model.type(digit: digit)
        return true
    }

    // MARK: Touch and mouse

    /// A tap shows or hides the controls; a swipe across the picture changes
    /// channel (left for the next, as the remote's right); a double click is
    /// full screen. The mouse moving brings the controls up for a while.
    private func connectPointer() {
        stage.on("pointerdown") { [weak self] event in
            guard let self, event.target.object.map({ self.stageBar.object.contains!($0).boolean == true }) != true else { return }
            self.gesture = (event.clientX.number ?? 0, event.clientY.number ?? 0, event.pointerType.string == "mouse")
        }
        stage.on("pointerup") { [weak self] event in
            guard let self, let start = self.gesture else { return }
            self.gesture = nil
            let dx = (event.clientX.number ?? 0) - start.x
            let dy = (event.clientY.number ?? 0) - start.y
            if abs(dx) > 60, abs(dx) > 1.5 * abs(dy), !start.mouse {
                self.model.perform(dx < 0 ? .channelUp : .channelDown)
            } else if abs(dx) < 12, abs(dy) < 12 {
                self.toggleControls()
            }
        }
        stage.on("pointercancel") { [weak self] _ in self?.gesture = nil }
        stage.on("dblclick") { _ in FullScreen.toggle() }
        element.on("mousemove") { [weak self] _ in self?.reveal() }
        element.on("focusin") { [weak self] _ in self?.reveal(hideAfter: nil) }
        element.on("focusout") { [weak self] _ in self?.reveal() }
    }

    private var isRevealed: Bool { element.object.classList.contains("revealed").boolean == true }

    private func toggleControls() {
        if isRevealed { hideControls() } else { reveal() }
    }

    /// Shows the controls, and hides them again after `seconds` still.
    private func reveal(hideAfter seconds: Double? = 4) {
        guard model.takesRemoteInput, !isCovered else { return }
        element.classed("revealed", true)
        hiding?.cancel()
        guard let seconds else { return }
        hiding = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.hideControls()
        }
    }

    private func hideControls() {
        hiding?.cancel()
        // Never while a control has focus: the keyboard is using them.
        if let focused = DOM.focused, now.element.object.contains!(focused).boolean == true
            || stageBar.object.contains!(focused).boolean == true { return }
        element.classed("revealed", false)
    }

    // MARK: Drawing

    /// The two decks, the active one on top; hidden while changing channel
    /// or between programmes.
    private func drawPicture() {
        for (index, deck) in player.decks.enumerated() {
            guard let deck = deck as? VideoDeck else { continue }
            deck.element.classed("active", index == player.activeIndex)
        }
        decks.classed("hidden", model.hidesVideo || model.changingChannel)
        soundNote.hidden = !SoundUnlock.shared.isNeeded
    }

    private func drawCards() {
        if let content = model.stationCard {
            if stationCard?.content != content {
                stationCard?.close()
                let card = StationCard(content: content)
                stationCard = card
                cards.replaceChildren([card.element])
            }
            return
        }
        stationCard?.close()
        stationCard = nil
        cards.replaceChildren(model.statusCard.map { [Self.statusCard($0)] } ?? [])
    }

    private func drawNow() {
        let content = model.banner(at: clock.now)
        now.draw(content, paused: player.status.isPaused, showing: !isCovered && model.bannerIsShowing)
        badge.classed("showing", !isCovered && model.showsBreakBadge)
        if model.showsBreakBadge {
            badge.replaceChildren([Icon.tv.element, El("span", text: BreakText.title + (model.breakBadgeBackAt.map { " · \($0)" } ?? ""))])
        }
        numberEntry.hidden = model.numberEntryText == nil
        numberEntry.text = model.numberEntryText ?? ""
        numberEntry.classed("notice", surfer.notice != nil)
        // Said once per channel and programme, not every second.
        let said = "Channel \(content.channelNumber), \(content.channelName). "
            + (content.programme.map { "\($0.title). \($0.subtitle ?? "")" } ?? "")
        if said != announced {
            announced = said
            announcer.text = said
        }
    }

    /// The lineup under the picture, with the channels as they are now: a
    /// new schedule code, or a channel added, rebuilds them.
    private func drawLineup() {
        if lineupRows.show(surfer.channels) {
            lineup.replaceChildren([lineupTitle] + lineupRows.rows.map(\.row))
        }
        lineupRows.draw(at: lineupClock.now, current: player.schedule.channel.number)
    }

    private func drawFullScreen() {
        let on = FullScreen.isOn
        let label = on ? "Leave full screen" : "Full screen"
        fullScreen.replaceChildren([(on ? Icon.exitFullScreen : Icon.fullScreen).element])
        fullScreen.attribute("aria-label", label).attribute("title", label)
    }

    /// Black over everything while it's closed, fading as the model says.
    private func drawCurtain() {
        let curtain = model.curtain
        self.curtain.style("transition-duration", "\(curtain.fade)s")
        self.curtain.style("transition-timing-function", curtain.closed ? "ease-in" : "ease-out")
        self.curtain.classed("closed", curtain.closed)
    }

    /// The channel list, guide or Settings, whichever is open. What's under
    /// it is out of reach (inert) meanwhile.
    private func drawPanels() {
        let key = model.showingSettings ? "settings" : model.showingGuide ? "guide" : model.showingList ? "list" : ""
        // Settings closed by any route: back to live TV, or to the guide it came from.
        if wasShowingSettings && !model.showingSettings { model.settingsClosed() }
        wasShowingSettings = model.showingSettings
        guard key != openPanelKey else { return }
        openPanelKey = key
        openPanel?.close()
        let current = player.schedule.channel.number
        let model = model
        let select: (Int) -> Void = { model.select(channel: $0) }
        let remote: (RemoteAction) -> Void = { model.perform($0) }
        openPanel = switch key {
        case "list": ChannelListPanel(channels: surfer.channels, currentNumber: current, onSelect: select, onRemote: remote)
        case "guide": GuidePanel(channels: surfer.channels, currentNumber: current, onSelect: select, onRemote: remote)
        case "settings": SettingsPanel(app: app, model: model)
        default: nil
        }
        for part in [stage, now.element, lineup] { part.inert = openPanel != nil }
        element.classed("panel-open", openPanel != nil)
        overlay.replaceChildren(openPanel.map { [$0.element] } ?? [])
        openPanel?.appeared()
        if openPanel != nil { hideControls() }
    }

    /// The model's timers, restarted whenever their trigger changes.
    private func drawTimers() {
        let model = model
        bannerTimer.run(for: model.bannerTrigger) { await model.runBannerTimer() }
        curtainTimer.run(for: model.curtainTrigger) { await model.runCurtain() }
        stationCardTimer.run(for: model.curtainTrigger) { await model.runStationCard() }
    }

    /// The picture's card for gaps and playback failures.
    private static func statusCard(_ content: StatusCardContent) -> El {
        switch content {
        case .upNext(let heading, let title, let when):
            let card = El("div", "status-card", [El("p", "heading", text: heading)])
            if let title { card.append(El("p", "title", text: title)) }
            card.append(El("p", "when", text: when))
            return card
        case .failed(let message, let retryAt):
            return El("div", "status-card", [
                Icon.warning.element,
                El("p", "title", text: message).attribute("role", "alert"),
                El("p", "when", text: "Trying again at \(retryAt.clockTime)…"),
            ])
        }
    }
}

/// What's on, and the controls: under the picture on a phone, a card over
/// it on larger screens. While surfing, it previews the channel being moved to.
@MainActor final class NowPanel {
    let element = El("section", "now").attribute("aria-label", "Now playing")
    private let number = El("span", "channel-number")
    private let name = El("span", "channel-name")
    private let clock = El("span", "clock")
    private let status = El("p", "status")
    private let title = El("h2", "programme-title")
    private let subtitle = El("p", "programme-subtitle")
    private let bar = El("div", "playhead").attribute("role", "progressbar").attribute("aria-label", "Programme progress")
        .attribute("aria-valuemin", "0").attribute("aria-valuemax", "100")
    private let fill = El("div", "playhead-fill")
    private let started = El("span")
    private let time = El("span")
    private let pause: El
    private let hint = El("p", "hint")
    private let diagnostics = El("div", "diagnostics")

    init(perform: @escaping @MainActor (RemoteAction) -> Void) {
        pause = El.button("Pause", icon: .pause, "icon-button main-button", labelHidden: true) { perform(.pauseOrJumpToLive) }
        func control(_ title: String, _ icon: Icon, _ action: RemoteAction) -> El {
            El.button(title, icon: icon, "icon-button", labelHidden: true) { perform(action) }
        }
        bar.append(fill)
        element.append(
            El("div", "now-head", [El("div", "channel-chip", [number, name]), clock]),
            status, title, subtitle, bar, El("div", "times", [started, time]),
            El("div", "transport", [
                El("div", "group", [control("Channel down", .previous, .channelDown), pause, control("Channel up", .next, .channelUp)]),
                El("div", "group", [
                    control("Info", .info, .showInfo), control("Guide", .guide, .openGuide),
                    control("Channel list", .list, .openChannelList), control(SettingsText.title, .settings, .openSettings),
                ]),
            ]),
            hint, diagnostics)
    }

    func draw(_ content: BannerContent, paused: Bool, showing: Bool) {
        element.classed("showing", showing)
        number.text = String(content.channelNumber)
        name.text = content.channelName
        clock.text = Date.now.clockTime
        let programme = content.programme
        // Every part keeps its place whatever is missing, so flicking
        // through channels doesn't reshape it.
        title.text = programme?.title ?? content.channelName
        subtitle.text = programme?.subtitle ?? " "
        status.text = programme?.status ?? ""
        bar.style("visibility", programme == nil ? "hidden" : "visible")
        let percent = ((programme?.progress ?? 0) * 100).rounded()
        fill.style("width", "\(percent)%")
        bar.attribute("aria-valuenow", String(Int(percent)))
        started.text = programme?.started ?? " "
        time.text = programme?.time ?? " "
        let label = paused ? "Jump to live" : "Pause"
        if pause.object.getAttribute!("aria-label").string != label {
            pause.replaceChildren([(paused ? Icon.play : Icon.pause).element])
            pause.attribute("aria-label", label).attribute("title", label)
        }
        hint.text = content.hint
        diagnostics.replaceChildren(content.diagnostics.map { El("div", text: $0) })
    }
}
