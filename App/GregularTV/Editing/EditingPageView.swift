import GregularScreens
import SwiftUI

/// Settings › Edit from a Phone or Computer: while this screen is open, the
/// editing page is served on the home network, and the screen shows where
/// to open it and its one-time code. Closing the screen stops it.
struct EditingPageView: View {
    let app: AppModel

    @State private var server = EditingServer()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SettingsRows.page(opacity: 1) {
            Text("Edit from a Phone or Computer").font(.largeTitle).bold()

            switch server.status {
            case .starting:
                SettingsRows.section(nil) { SettingsRows.info("Starting", "…") }
            case .failed(let message):
                SettingsRows.section(nil, footer: [message]) { SettingsRows.info("Not available", "") }
            case .ready(let addresses):
                SettingsRows.section("On a phone or computer on the same network, open", footer: [
                    addresses.count > 1 ? "Any of these addresses works." : nil,
                ]) {
                    ForEach(addresses, id: \.self) { address in
                        Text(address).font(.system(size: 64, weight: .bold, design: .monospaced))
                            .padding(.horizontal, SettingsRowStyle.inset)
                    }
                }
                if let page = server.page {
                    SettingsRows.section("Then enter this code", footer: [
                        page.isLocked ? "Locked after \(EditingPage.mostWrongCodes) wrong codes. Close this screen and open it again for a new code." : nil,
                        page.lastSaved.map { "Saved from the page at \($0.formatted(date: .omitted, time: .shortened)). Your channels have been rebuilt." },
                    ]) {
                        Text(page.isLocked ? "Locked" : page.code.chunked)
                            .font(.system(size: 96, weight: .heavy, design: .monospaced))
                            .padding(.horizontal, SettingsRowStyle.inset)
                    }
                }
            }

            SettingsRows.section(nil, footer: [
                "The page edits your channels and set times, the same ones as in Settings. It only works while this screen is open, and only from your home network. It never sees your Jellyfin address, password or token. Turn \u{201C}Edit from a phone or computer\u{201D} off in Settings to hide this screen.",
            ]) {
                SettingsRows.row("Done") { dismiss() }
            }
        }
        .onAppear { server.start(app: app) }
        .onDisappear { server.stop() }
        .debugMenuKeyCloses()
    }
}

private extension String {
    /// "482193" → "482 193", easier to read across a room.
    var chunked: String {
        count == 6 ? "\(prefix(3)) \(suffix(3))" : self
    }
}
