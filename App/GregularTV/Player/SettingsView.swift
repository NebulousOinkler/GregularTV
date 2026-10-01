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
            Text("Settings").font(.largeTitle).bold()

            SettingsRows.section("Streaming quality", footer: [
                app.showsDiagnostics ? player.streamDescription.map { "Now playing: \($0)" } : nil,
                "Lower quality saves bandwidth but makes the server transcode, which takes more of its processing power. If your server is short on CPU rather than bandwidth, Maximum may work best.",
            ]) {
                ForEach(StreamingQuality.allCases) { quality in
                    SettingsRows.row(quality.label,
                                     detail: quality == .auto ? "Measures how fast your server can stream right now, and backs off when it's busy." : nil,
                                     checked: quality == player.quality) {
                        app.setStreamingQuality(quality)
                        dismiss()
                    }
                    .focused($focusedQuality, equals: quality)
                }
            }

            if let programme = player.fixableProgramme?.item.displayTitle {
                SettingsRows.section("Trouble with \u{201C}\(programme)\u{201D}?", footer: [
                    "For this programme only: the next programme, or changing channel, goes back to standard. These help when Jellyfin has to convert the programme and can't keep up, since a lower quality is quicker to convert. A programme that plays as-is will be converted at the lower quality.",
                ]) {
                    fixRow(.stepDown, "Step Down Quality",
                           detail: "Restarts it one step lower, and steps down again whenever it pauses to buffer.")
                    fixRow(.hd720, "Play at 720p", detail: "Restarts it at 720p (4 Mbps).")
                    fixRow(.standard, "Standard", detail: "Back to your streaming quality setting.")
                }
            }

            SettingsRows.section("Schedule code", footer: [
                codeError,
                "The code sets the running order on every channel. Anyone using the same code, with the same Jellyfin library and channels, sees the same programmes at the same time. Changing it reshuffles every channel.",
            ]) {
                SettingsRows.info("Current code", app.scheduleCode.description)
                TextField("Enter a code, like 7KQM2-X9PDA", text: $codeText)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .onSubmit(applyTypedCode)
                SettingsRows.row("Use a New Random Code") {
                    app.setScheduleCode(.random())
                    dismiss()
                }
            }

            yourChannels

            SettingsRows.section("Commercials", footer: [
                "When off, breaks between programmes are blank, with the Up Next card showing what's on next and when. Programmes still start at the same times, so you stay in step with everyone using the same schedule code.",
            ]) {
                SettingsRows.row("Play commercials", value: app.playsCommercials ? "On" : "Off") {
                    app.setPlaysCommercials(!app.playsCommercials)
                }
            }

            SettingsRows.section("Diagnostics", footer: [
                app.showsDiagnostics ? commercialsStatus.map { "Commercials: \($0)" } : nil,
                "Adds a technical line to the info banner: quality, whether the server is transcoding and why, buffering, and how far behind live playback is. Useful when something isn't playing well.",
            ]) {
                SettingsRows.row("Show playback diagnostics", value: app.showsDiagnostics ? "On" : "Off") {
                    app.setShowsDiagnostics(!app.showsDiagnostics)
                }
            }

            SettingsRows.section("Server", footer: [
                "All Servers goes to the main page, to watch another server or add one. Menu from live TV goes there too; the channel plays on behind it.",
            ]) {
                if let server = app.currentServer {
                    SettingsRows.row("Watching", detail: server.name == nil ? nil : server.address, value: server.title) {}
                }
                SettingsRows.row("All Servers") {
                    dismiss()
                    app.showMainPage()
                }
                SettingsRows.confirmedRow(app.signOutConfirmation) {
                    dismiss()
                    Task { await app.signOut() }
                }
            }

            SettingsRows.section(nil, footer: [RemoteControls.hint(for: RemoteControls.settings, onScreen: [.close: "Done"])]) {
                SettingsRows.row("Done") { dismiss() }
            }
        }
        .defaultFocus($focusedQuality, player.quality)
        .task {
            // In case the default didn't take (it's the top row otherwise).
            try? await Task.sleep(for: .milliseconds(100))
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
        SettingsRows.section("Your channels", footer: [
            app.customChannels.isEmpty ? "None yet." : nil,
            "Your own channels join the guide like any other. They're saved on this Apple TV: the name, number and the genres, series, tags and years in each one's rule. Nothing else from your library is kept.",
            howToEdit,
        ]) {
            ForEach(app.customChannels, id: \.self) { channel in
                SettingsRows.row("\(channel.number)  \(channel.name)", detail: channel.summary) {}
            }
        }

        SettingsRows.section("Set times", footer: [
            app.setTimes.isEmpty ? "None yet." : nil,
            "A series or film at fixed times on a channel. At every other time the channel stays the same as for everyone with your schedule code. They're saved on this Apple TV: the channel, the names you picked and the times.",
            howToEdit,
        ]) {
            ForEach(app.setTimesChannels) { channel in
                SettingsRows.row(channel.title, detail: channel.detail) {}
            }
        }

        SettingsRows.section("Edit from a phone or computer", footer: [
            "When on, you can make and change your channels and set times in a web browser on a phone or computer on your home network, with a keyboard and search, while the editing screen is open here. Off, they can't be changed. Nothing is kept or sent anywhere else either way.",
        ]) {
            SettingsRows.row("Editing page", value: app.allowsEditingPage ? "On" : "Off") {
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
            codeError = "A code is 10 letters and digits, like 7KQM2-X9PDA."
            return
        }
        app.setScheduleCode(code)
        dismiss()
    }
}
