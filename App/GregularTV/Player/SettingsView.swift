import GregularTVCore
import SwiftUI

/// Opened by clicking and holding while watching, or from the guide.
/// Closed by Menu, Play/Pause, or the Done button, so no single key is required.
struct SettingsView: View {
    let current: StreamingQuality
    let streamDescription: String?
    /// The programme on now, if one is, and the fix it's using.
    let programmeTitle: String?
    let programmeFix: ChannelPlayer.ProgrammeFix
    let scheduleCode: ScheduleCode
    let showsDiagnostics: Bool
    let playsCommercials: Bool
    let commercialsStatus: String?
    let onSelect: (StreamingQuality) -> Void
    let onProgrammeFix: (ChannelPlayer.ProgrammeFix) -> Void
    let onScheduleCodeChange: (ScheduleCode) -> Void
    let onShowsDiagnosticsChange: (Bool) -> Void
    let onPlaysCommercialsChange: (Bool) -> Void
    let onSignOut: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var codeText = ""
    @State private var codeError: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(StreamingQuality.allCases) { quality in
                        Button {
                            onSelect(quality)
                            dismiss()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(quality.label)
                                    if quality == .auto {
                                        Text("Measures how fast your server can stream right now, and backs off when it's busy.")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if quality == current { Image(systemName: "checkmark") }
                            }
                        }
                    }
                } header: {
                    Text("Streaming quality")
                } footer: {
                    VStack(alignment: .leading, spacing: 8) {
                        if showsDiagnostics, let streamDescription { Text("Now playing: \(streamDescription)") }
                        Text("Lower quality saves bandwidth but makes the server transcode, which takes more of its processing power. If your server is short on CPU rather than bandwidth, Maximum may work best.")
                    }
                }

                if let programmeTitle {
                    Section {
                        fixButton(.stepDown, "Step Down Quality",
                                  detail: "Restarts it one step lower, and steps down again whenever it pauses to buffer.")
                        fixButton(.hd720, "Play at 720p",
                                  detail: "Restarts it at 720p (4 Mbps).")
                        fixButton(.standard, "Standard",
                                  detail: "Back to your streaming quality setting.")
                    } header: {
                        Text("Trouble with \u{201C}\(programmeTitle)\u{201D}?")
                    } footer: {
                        Text("For this programme only: the next programme, or changing channel, goes back to standard. These help when Jellyfin has to convert the programme and can't keep up, since a lower quality is quicker to convert. A programme that plays as-is will be converted at the lower quality.")
                    }
                }

                Section {
                    HStack {
                        Text("Current code")
                        Spacer()
                        Text(scheduleCode.description).font(.title3.monospaced()).bold()
                    }
                    TextField("Enter a code, like 7KQM2-X9PDA", text: $codeText)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .onSubmit(applyTypedCode)
                    Button("Use a New Random Code") {
                        onScheduleCodeChange(.random())
                        dismiss()
                    }
                } header: {
                    Text("Schedule code")
                } footer: {
                    VStack(alignment: .leading, spacing: 8) {
                        if let codeError { Text(codeError).foregroundStyle(.red) }
                        Text("The code sets the running order on every channel. Anyone using the same code, with the same Jellyfin library and channels, sees the same programmes at the same time. Changing it reshuffles every channel.")
                    }
                }

                Section {
                    Toggle("Play commercials", isOn: Binding(get: { playsCommercials },
                                                             set: { onPlaysCommercialsChange($0) }))
                } header: {
                    Text("Commercials")
                } footer: {
                    Text("When off, breaks between programmes are blank, with the Up Next card showing what's on next and when. Programmes still start at the same times, so you stay in step with everyone using the same schedule code.")
                }

                Section {
                    Toggle("Show playback diagnostics", isOn: Binding(get: { showsDiagnostics },
                                                                      set: { onShowsDiagnosticsChange($0) }))
                } header: {
                    Text("Diagnostics")
                } footer: {
                    VStack(alignment: .leading, spacing: 8) {
                        if showsDiagnostics, let commercialsStatus { Text("Commercials: \(commercialsStatus)") }
                        Text("Adds a technical line to the info banner: quality, whether the server is transcoding and why, buffering, and how far behind live playback is. Useful when something isn't playing well.")
                    }
                }

                Section {
                    Button("Done") { dismiss() }
                    Button("Sign Out", role: .destructive) {
                        dismiss()
                        onSignOut()
                    }
                } footer: {
                    (Text("Menu, ") + Text(Image(systemName: "playpause.fill")) + Text(" or Done to close"))
                }
            }
            .navigationTitle("Settings")
        }
        .onExitCommand { dismiss() }
        .onPlayPauseCommand { dismiss() }
    }

    private func fixButton(_ fix: ChannelPlayer.ProgrammeFix, _ title: String, detail: String) -> some View {
        Button {
            onProgrammeFix(fix)
            dismiss()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if fix == programmeFix { Image(systemName: "checkmark") }
            }
        }
    }

    private func applyTypedCode() {
        guard let code = ScheduleCode(codeText) else {
            codeError = "A code is 10 letters and digits, like 7KQM2-X9PDA."
            return
        }
        onScheduleCodeChange(code)
        dismiss()
    }
}
