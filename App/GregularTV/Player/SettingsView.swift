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
    @State private var channelCodeText = ""
    @State private var channelError: String?
    @State private var setTimesCodeText = ""
    @State private var setTimesError: String?
    @State private var choosingChannel = false
    @State private var editor: Editor?
    @State private var setTimesEditor: SetTimesEditor?

    /// The channel editor, while it's open.
    private struct Editor: Identifiable {
        let id = UUID()
        let model: ChannelEditorModel
    }

    /// The set-times editor, while it's open.
    private struct SetTimesEditor: Identifiable {
        let id = UUID()
        let model: SetTimesEditorModel
    }

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

            SettingsRows.section("Your channels", footer: [
                channelError,
                "Custom channels are saved on this Apple TV as their channel codes: the name, number and the genre, series or tag you picked. Nothing else from your library is kept. To share one, type its code (shown when you edit it) into another Apple TV.",
            ]) {
                ForEach(app.customChannels, id: \.self) { channel in
                    SettingsRows.row("\(channel.number)  \(channel.name)", detail: channel.summary) { openEditor(editing: channel) }
                }
                SettingsRows.row("Add a Channel") { openEditor(editing: nil) }
                TextField("Or enter a channel code from another Apple TV", text: $channelCodeText)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .onSubmit(addTypedChannel)
            }

            setTimesSection

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

            SettingsRows.section(nil, footer: ["\(RemoteControls.hint(for: RemoteControls.settings)) · Done to close"]) {
                SettingsRows.row("Done") { dismiss() }
                SettingsRows.confirmedRow(app.signOutConfirmation) {
                    dismiss()
                    Task { await app.signOut() }
                }
            }
        }
        .remoteControls(RemoteControls.settings) { action in
            if action == .close { dismiss() } else { onRemote(action) }
        }
        #if DEBUG
        .onAppear {
            if DebugOptions.opensChannelEditor { openEditor(editing: nil) }
            if DebugOptions.opensSetTimesEditor { openSetTimesEditor(forChannel: 1) }
        }
        #endif
        .fullScreenCover(item: $editor) { editor in
            ChannelEditorView(model: editor.model,
                              onSave: { save($0, replacing: editor.model.original) },
                              onDelete: editor.model.original.map { original in { app.delete(original) } })
        }
        .fullScreenCover(item: $setTimesEditor) { editor in
            SetTimesEditorView(model: editor.model,
                               onSave: { setTimesError = app.save($0, replacing: editor.model.original) },
                               onDelete: editor.model.original.map { original in { app.delete(original) } })
        }
    }

    /// Programmes at set times on a channel, for this household only.
    @ViewBuilder private var setTimesSection: some View {
        SettingsRows.section("Set times", footer: [
            setTimesError,
            "Set a series or film to air at fixed times on a channel. At every other time the channel stays the same as for everyone with your schedule code. Set times are saved on this Apple TV as their set-times codes: the channel, the names you picked and the times. To share them, type the code (shown when you edit them) into another Apple TV.",
        ]) {
            let channels = app.setTimesChannels
            ForEach(channels.filter { $0.setTimes != nil }) { channel in
                SettingsRows.row(channel.title, detail: channel.detail) { openSetTimesEditor(forChannel: channel.number) }
            }
            SettingsRows.row("Set Times on a Channel", value: choosingChannel ? "Done" : "Choose") { choosingChannel.toggle() }
            if choosingChannel {
                ForEach(channels.filter { $0.setTimes == nil }) { channel in
                    SettingsRows.row(channel.title) {
                        choosingChannel = false
                        openSetTimesEditor(forChannel: channel.number)
                    }
                }
            }
            TextField("Or enter a set-times code from another Apple TV", text: $setTimesCodeText)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .onSubmit(addTypedSetTimes)
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

    private func openEditor(editing channel: CustomChannel?) {
        editor = app.makeChannelEditor(editing: channel).map { Editor(model: $0) }
    }

    /// Saving rebuilds the channels, which closes Settings.
    private func save(_ channel: CustomChannel, replacing original: CustomChannel?) {
        channelError = app.save(channel, replacing: original)
    }

    private func openSetTimesEditor(forChannel number: Int) {
        setTimesEditor = app.makeSetTimesEditor(forChannel: number).map { SetTimesEditor(model: $0) }
    }

    private func addTypedSetTimes() {
        setTimesError = app.addSetTimes(code: setTimesCodeText)
        if setTimesError == nil { dismiss() }
    }

    private func addTypedChannel() {
        channelError = app.addChannel(code: channelCodeText)
        if channelError == nil { dismiss() }
    }
}
