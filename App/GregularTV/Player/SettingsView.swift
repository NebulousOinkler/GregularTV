import GregularTVCore
import SwiftUI

/// Opened by clicking and holding while watching, or from the guide.
/// Closed by the Done button, or the buttons in `RemoteControls.settings`
/// (Menu and Play/Pause as shipped), so no single key is required.
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
    /// Buttons mapped in `RemoteControls.settings` to anything but closing.
    let onRemote: (RemoteAction) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var codeText = ""
    @State private var codeError: String?

    var body: some View {
        // A scroll view of our own rows, not a List: the system's focus
        // highlight in a List left light text on a light background on a TV.
        ScrollView {
            VStack(alignment: .leading, spacing: 56) {
                Text("Settings").font(.largeTitle).bold()

                section("Streaming quality", footer: [
                    showsDiagnostics ? streamDescription.map { "Now playing: \($0)" } : nil,
                    "Lower quality saves bandwidth but makes the server transcode, which takes more of its processing power. If your server is short on CPU rather than bandwidth, Maximum may work best.",
                ]) {
                    ForEach(StreamingQuality.allCases) { quality in
                        row(quality.label,
                            detail: quality == .auto ? "Measures how fast your server can stream right now, and backs off when it's busy." : nil,
                            checked: quality == current) {
                            onSelect(quality)
                            dismiss()
                        }
                    }
                }

                if let programmeTitle {
                    section("Trouble with \u{201C}\(programmeTitle)\u{201D}?", footer: [
                        "For this programme only: the next programme, or changing channel, goes back to standard. These help when Jellyfin has to convert the programme and can't keep up, since a lower quality is quicker to convert. A programme that plays as-is will be converted at the lower quality.",
                    ]) {
                        fixRow(.stepDown, "Step Down Quality",
                               detail: "Restarts it one step lower, and steps down again whenever it pauses to buffer.")
                        fixRow(.hd720, "Play at 720p", detail: "Restarts it at 720p (4 Mbps).")
                        fixRow(.standard, "Standard", detail: "Back to your streaming quality setting.")
                    }
                }

                section("Schedule code", footer: [
                    codeError,
                    "The code sets the running order on every channel. Anyone using the same code, with the same Jellyfin library and channels, sees the same programmes at the same time. Changing it reshuffles every channel.",
                ]) {
                    HStack {
                        Text("Current code")
                        Spacer()
                        Text(scheduleCode.description).font(.title3.monospaced()).bold()
                    }
                    .padding(.horizontal, SettingsRowStyle.inset)
                    TextField("Enter a code, like 7KQM2-X9PDA", text: $codeText)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .onSubmit(applyTypedCode)
                    row("Use a New Random Code") {
                        onScheduleCodeChange(.random())
                        dismiss()
                    }
                }

                section("Commercials", footer: [
                    "When off, breaks between programmes are blank, with the Up Next card showing what's on next and when. Programmes still start at the same times, so you stay in step with everyone using the same schedule code.",
                ]) {
                    row("Play commercials", value: playsCommercials ? "On" : "Off") {
                        onPlaysCommercialsChange(!playsCommercials)
                    }
                }

                section("Diagnostics", footer: [
                    showsDiagnostics ? commercialsStatus.map { "Commercials: \($0)" } : nil,
                    "Adds a technical line to the info banner: quality, whether the server is transcoding and why, buffering, and how far behind live playback is. Useful when something isn't playing well.",
                ]) {
                    row("Show playback diagnostics", value: showsDiagnostics ? "On" : "Off") {
                        onShowsDiagnosticsChange(!showsDiagnostics)
                    }
                }

                section(nil, footer: ["\(RemoteControls.hint(for: RemoteControls.settings)) · Done to close"]) {
                    row("Done") { dismiss() }
                    row("Sign Out", role: .destructive) {
                        dismiss()
                        onSignOut()
                    }
                }
            }
            .frame(maxWidth: 1200)
            .padding(.horizontal, 60)
            .padding(.vertical, 60)
            .frame(maxWidth: .infinity)
        }
        .background(Color.black.opacity(0.92).ignoresSafeArea())
        .remoteControls(RemoteControls.settings) { action in
            if action == .close { dismiss() } else { onRemote(action) }
        }
    }

    /// A heading, its rows, and notes underneath (nil notes are left out).
    private func section(_ title: String?, footer: [String?],
                         @ViewBuilder rows: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                Text(title).font(.headline).foregroundStyle(.secondary)
                    .padding(.horizontal, SettingsRowStyle.inset)
            }
            rows()
            ForEach(footer.compactMap { $0 }, id: \.self) { note in
                Text(note).font(.caption).foregroundStyle(.secondary)
                    .padding(.horizontal, SettingsRowStyle.inset)
            }
        }
        .focusSection()
    }

    private func row(_ title: String, detail: String? = nil, value: String? = nil, checked: Bool = false,
                     role: ButtonRole? = nil, action: @escaping () -> Void) -> some View {
        Button(role: role, action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                    if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
                }
                Spacer()
                if let value { Text(value).foregroundStyle(.secondary) }
                if checked { Image(systemName: "checkmark") }
            }
        }
        .buttonStyle(SettingsRowStyle())
    }

    private func fixRow(_ fix: ChannelPlayer.ProgrammeFix, _ title: String, detail: String) -> some View {
        row(title, detail: detail, checked: fix == programmeFix) {
            onProgrammeFix(fix)
            dismiss()
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

/// A settings row. Highlighted, it's white with black text; otherwise white
/// text on a faint row. The colours are set here, not left to the system,
/// so text always stands out from the highlight. (`.secondary` text follows
/// along, as grey on either.)
private struct SettingsRowStyle: ButtonStyle {
    static let inset: CGFloat = 32

    func makeBody(configuration: Configuration) -> some View {
        Row(configuration: configuration)
    }

    private struct Row: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isFocused) private var isFocused

        var body: some View {
            configuration.label
                .font(.body)
                .foregroundStyle(configuration.role == .destructive ? Color.red : isFocused ? Color.black : Color.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, SettingsRowStyle.inset)
                .padding(.vertical, 22)
                .background(isFocused ? Color.white : Color.white.opacity(configuration.isPressed ? 0.25 : 0.08),
                            in: RoundedRectangle(cornerRadius: 16))
                .scaleEffect(isFocused ? 1.02 : 1)
                .shadow(color: .black.opacity(isFocused ? 0.4 : 0), radius: 12, y: 6)
                .animation(.easeOut(duration: 0.15), value: isFocused)
        }
    }
}
