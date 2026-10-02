import GregularCore
import GregularScreens
import JavaScriptKit

/// Settings, over live TV: the same choices and words as on Apple TV
/// (`SettingsText`), plus the channel editor and forgetting this browser.
/// Opened with S, the control bar, or the guide; closed by Done or
/// `RemoteControls.settings`' buttons (Escape and Space, as shipped).
@MainActor final class SettingsPanel: Page, KeyTarget {
    let element: El
    private let app: AppModel
    private let model: WatchModel
    private let content: El
    private var redraw: Redraw?
    private var codeError: String?
    private var editor: ChannelEditor?

    init(app: AppModel, model: WatchModel) {
        self.app = app
        self.model = model
        let (sheet, body) = Parts.sheet("settings", title: SettingsText.title) { model.showingSettings = false }
        element = sheet
        content = body
        redraw = Redraw { [weak self] in self?.draw() }
        Keys.take(self)
    }

    /// Start on the quality in use, not the top row.
    func appeared() {
        let rows = Focus.focusable(in: content)
        (rows.first { $0.object.getAttribute!("aria-checked").string == "true" && $0.object.getAttribute!("role").string == "radio" }
            ?? rows.first)?.focus()
    }

    func close() {
        redraw?.stop()
        editor?.close()
        Keys.release(self)
    }

    func press(_ button: RemoteButton) -> Bool {
        if editor != nil { return false }
        return Overlay.press(button, table: RemoteControls.settings, within: element) { [weak self] action in
            if action == .close { self?.dismiss() } else { self?.model.perform(action) }
        }
    }

    private func dismiss() {
        model.showingSettings = false
    }

    private func draw() {
        // Keep focus on the same row (by its title) across a redraw.
        let focusedTitle = DOM.focused?.querySelector?(".row-title").object?.textContent.string
        let scroll = content.object.scrollTop
        let player = model.player
        var sections: [El] = []

        sections.append(Parts.section(SettingsText.quality, footer: [
            app.showsDiagnostics ? player.streamDescription.map(SettingsText.nowPlaying) : nil,
            SettingsText.qualityNote,
        ], role: "radiogroup", rows: StreamingQuality.allCases.map { quality in
            Parts.choice(quality.label, detail: quality == .auto ? SettingsText.autoDetail : nil, checked: quality == player.quality) { [app] in
                app.setStreamingQuality(quality)
                self.dismiss()
            }
        }))

        if let programme = player.fixableProgramme?.item.displayTitle {
            sections.append(Parts.section(SettingsText.trouble(with: programme), footer: [SettingsText.troubleNote], role: "radiogroup",
                                          rows: SettingsText.fixes.map { fix in
                Parts.choice(fix.title, detail: fix.detail, checked: fix.fix == player.programmeFix) {
                    player.setProgrammeFix(fix.fix)
                    self.dismiss()
                }
            }))
        }

        sections.append(Parts.section(SettingsText.scheduleCode, footer: [codeError, SettingsText.scheduleCodeNote], rows: [
            Parts.info(SettingsText.currentCode, app.scheduleCode.description),
            codeField(),
            Parts.row(SettingsText.newRandomCode) { [app] in
                app.setScheduleCode(.random())
                self.dismiss()
            },
        ]))

        let howToEdit = "Make and change them with Edit Channels."
        sections.append(Parts.section(SettingsText.yourChannels, footer: [
            app.customChannels.isEmpty ? SettingsText.noneYet : nil,
            SettingsText.yourChannelsNote(kept: "in this browser"),
            howToEdit,
        ], rows: app.customChannels.map { Parts.row("\($0.number)  \($0.name)", detail: $0.summary, action: nil) }
            + [Parts.row("Edit Channels") { [weak self] in self?.openEditor() }]))
        sections.append(Parts.section(SettingsText.setTimes, footer: [
            app.setTimes.isEmpty ? SettingsText.noneYet : nil,
            SettingsText.setTimesNote(kept: "in this browser"),
            howToEdit,
        ], rows: app.setTimesChannels.map { Parts.row($0.title, detail: $0.detail, action: nil) }))

        sections.append(Parts.section(SettingsText.commercials, footer: [SettingsText.commercialsNote], rows: [
            Parts.toggle(SettingsText.playCommercials, on: app.playsCommercials) { [app] in
                app.setPlaysCommercials(!app.playsCommercials)
            },
        ]))
        sections.append(Parts.section(SettingsText.diagnostics, footer: [
            app.showsDiagnostics ? model.commercialsDiagnostics(playsCommercials: app.playsCommercials,
                                                                libraryStatus: app.commercialsStatus).map(SettingsText.commercialsStatus) : nil,
            SettingsText.diagnosticsNote,
        ], rows: [
            Parts.toggle(SettingsText.showDiagnostics, on: app.showsDiagnostics) { [app] in
                app.setShowsDiagnostics(!app.showsDiagnostics)
            },
        ]))

        var serverRows: [El] = []
        if let server = app.currentServer {
            serverRows.append(Parts.row(SettingsText.watching, detail: server.name == nil ? nil : server.address, value: server.title, action: nil))
        }
        serverRows.append(Parts.row(SettingsText.allServers) { [app] in
            self.dismiss()
            app.showMainPage()
        })
        if let server = app.currentServer {
            let confirmation = app.signOutConfirmation(for: server)
            serverRows.append(Parts.row(confirmation.action, destructive: true) { [app] in
                Parts.confirm(confirmation) {
                    self.dismiss()
                    Task { await app.signOut(of: server) }
                }
            })
        }
        sections.append(Parts.section(SettingsText.server, footer: [
            SettingsText.serverNote(back: KeyboardControls.name(of: .menu) ?? "Esc"),
        ], rows: serverRows))

        let forget = Confirmation.forgetEverything("in this browser")
        sections.append(Parts.section("This browser", footer: [forget.detail], rows: [
            Parts.row(forget.action, destructive: true) {
                Parts.confirm(forget) { Task { await WebApp.forgetEverything() } }
            },
        ]))

        sections.append(Parts.section(nil, footer: [
            RemoteControls.hint(for: RemoteControls.settings, onScreen: [.close: SettingsText.done], names: KeyboardControls.names),
        ], rows: []))

        content.replaceChildren(sections)
        content.object.scrollTop = .number(scroll.number ?? 0)
        if let focusedTitle {
            Focus.focusable(in: content).first { $0.object.querySelector?(".row-title").object?.textContent.string == focusedTitle }?.focus()
        }
    }

    /// Type a schedule code and press Enter.
    private func codeField() -> El {
        let field = El("input", "code-field")
        field.attribute("type", "text").attribute("placeholder", "7KQM2-X9PDA")
            .attribute("aria-label", SettingsText.codePlaceholder).attribute("autocapitalize", "characters")
            .attribute("autocomplete", "off").attribute("spellcheck", "false")
        let form = El("form", "row field", [field])
        form.attribute("novalidate", "")
        form.on("submit") { [weak self, app] event in
            _ = event.preventDefault!()
            guard let self else { return }
            guard let code = ScheduleCode(field.object.value.string ?? "") else {
                self.codeError = SettingsText.badCode
                self.draw()
                return
            }
            app.setScheduleCode(code)
            self.dismiss()
        }
        return form
    }

    private func openEditor() {
        let editor = ChannelEditor(app: app) { [weak self] in self?.editor = nil }
        self.editor = editor
        El(DOM.document.body.object!).append(editor.element)
    }
}
