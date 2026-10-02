import GregularCore
import GregularScreens
import SwiftUI

/// Opened by clicking and holding while watching, or from the guide.
/// Closed by the Done button, or the buttons in `RemoteControls.settings`
/// (Menu and Play/Pause as shipped), so no single key is required.
struct SettingsView: View {
    let app: AppModel
    let player: ChannelPlayer
    /// For the diagnostics note: what's known about the commercials.
    let commercialsStatus: String?
    /// Buttons mapped in `RemoteControls.settings` to anything but closing.
    let onRemote: (RemoteAction) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var codeText = ""
    @State private var codeError: String?
    @State private var editingPage = false
    /// Settings opens on the quality in use, not the top row.
    @FocusState private var focusedQuality: StreamingQuality?

    var body: some View {
        SettingsRows.page {
            Text(SettingsText.title).font(.largeTitle).bold()

            SettingsRows.section(SettingsText.quality, footer: [
                app.showsDiagnostics ? player.streamDescription.map(SettingsText.nowPlaying) : nil,
                SettingsText.qualityNote,
            ]) {
                ForEach(StreamingQuality.allCases) { quality in
                    SettingsRows.row(quality.label,
                                     detail: quality == .auto ? SettingsText.autoDetail : nil,
                                     checked: quality == player.quality) {
                        app.setStreamingQuality(quality)
                        dismiss()
                    }
                    .focused($focusedQuality, equals: quality)
                }
            }

            if let programme = player.fixableProgramme?.item.displayTitle {
                SettingsRows.section(SettingsText.trouble(with: programme), footer: [SettingsText.troubleNote]) {
                    ForEach(SettingsText.fixes, id: \.title) { fixRow($0.fix, $0.title, detail: $0.detail) }
                }
            }

            SettingsRows.section(SettingsText.scheduleCode, footer: [codeError, SettingsText.scheduleCodeNote]) {
                SettingsRows.info(SettingsText.currentCode, app.scheduleCode.description)
                TextField(SettingsText.codePlaceholder, text: $codeText)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .onSubmit(applyTypedCode)
                SettingsRows.row(SettingsText.newRandomCode) {
                    app.setScheduleCode(.random())
                    dismiss()
                }
            }

            yourChannels

            SettingsRows.section(SettingsText.commercials, footer: [SettingsText.commercialsNote]) {
                SettingsRows.row(SettingsText.playCommercials, value: SettingsText.onOff(app.playsCommercials)) {
                    app.setPlaysCommercials(!app.playsCommercials)
                }
            }

            SettingsRows.section(SettingsText.diagnostics, footer: [
                app.showsDiagnostics ? commercialsStatus.map(SettingsText.commercialsStatus) : nil,
                SettingsText.diagnosticsNote,
            ]) {
                SettingsRows.row(SettingsText.showDiagnostics, value: SettingsText.onOff(app.showsDiagnostics)) {
                    app.setShowsDiagnostics(!app.showsDiagnostics)
                }
            }

            SettingsRows.section(SettingsText.server, footer: [SettingsText.serverNote(back: RemoteButton.menu.symbol)]) {
                if let server = app.currentServer {
                    SettingsRows.row(SettingsText.watching, detail: server.name == nil ? nil : server.address, value: server.title) {}
                }
                SettingsRows.row(SettingsText.allServers) {
                    dismiss()
                    app.showMainPage()
                }
                if let server = app.currentServer {
                    SettingsRows.confirmedRow(app.signOutConfirmation(for: server)) {
                        dismiss()
                        Task { await app.signOut(of: server) }
                    }
                }
            }

            SettingsRows.section(nil, footer: [RemoteControls.hint(for: RemoteControls.settings, onScreen: [.close: SettingsText.done])]) {
                SettingsRows.row(SettingsText.done) { dismiss() }
            }
        }
        .defaultFocus($focusedQuality, player.quality)
        .task {
            // In case the default didn't take (it's the top row otherwise).
            await FocusSettling.wait()
            if focusedQuality == nil || focusedQuality == StreamingQuality.allCases.first { focusedQuality = player.quality }
        }
        .remoteControls(RemoteControls.settings) { action in
            if action == .close { dismiss() } else { onRemote(action) }
        }
        #if DEBUG
        .onAppear {
            if DebugOptions.opensEditingPage { editingPage = true }
        }
        #endif
        .fullScreenCover(isPresented: $editingPage) {
            EditingPageView(app: app)
        }
    }

    /// Your channels and set times, listed here and made on the editing page.
    @ViewBuilder private var yourChannels: some View {
        let howToEdit = app.allowsEditingPage
            ? "Make and change them on the editing page: Open the Editing Page, below, and follow the steps on a phone or computer."
            : "Make and change them from a phone or computer: turn on the editing page, below."
        SettingsRows.section(SettingsText.yourChannels, footer: [
            app.customChannels.isEmpty ? SettingsText.noneYet : nil,
            SettingsText.yourChannelsNote(kept: "on this Apple TV"),
            howToEdit,
        ]) {
            ForEach(app.customChannels, id: \.self) { channel in
                SettingsRows.row("\(channel.number)  \(channel.name)", detail: channel.summary) {}
            }
        }

        SettingsRows.section(SettingsText.setTimes, footer: [
            app.setTimes.isEmpty ? SettingsText.noneYet : nil,
            SettingsText.setTimesNote(kept: "on this Apple TV"),
            howToEdit,
        ]) {
            ForEach(app.setTimesChannels) { channel in
                SettingsRows.row(channel.title, detail: channel.detail) {}
            }
        }

        SettingsRows.section("Edit from a phone or computer", footer: [
            "When on, you can make and change your channels and set times in a web browser on a phone or computer on your home network, with a keyboard and search, while the editing screen is open here. Off, they can't be changed. Nothing is kept or sent anywhere else either way.",
        ]) {
            SettingsRows.row("Editing page", value: SettingsText.onOff(app.allowsEditingPage)) {
                app.setAllowsEditingPage(!app.allowsEditingPage)
            }
            if app.allowsEditingPage {
                SettingsRows.row("Open the Editing Page") { editingPage = true }
            }
        }
    }

    private func fixRow(_ fix: ChannelPlayer.ProgrammeFix, _ title: String, detail: String) -> some View {
        SettingsRows.row(title, detail: detail, checked: fix == player.programmeFix) {
            player.setProgrammeFix(fix)
            dismiss()
        }
    }

    private func applyTypedCode() {
        guard let code = ScheduleCode(codeText) else {
            codeError = SettingsText.badCode
            return
        }
        app.setScheduleCode(code)
        dismiss()
    }
}
