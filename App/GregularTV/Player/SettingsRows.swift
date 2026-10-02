import GregularScreens
import SwiftUI

/// The pieces Settings and the channel editor are built from: sections of
/// rows on a dark screen, so both look and behave the same.
@MainActor
enum SettingsRows {
    /// A heading, its rows, and notes underneath (nil notes are left out).
    static func section(_ title: String?, footer: [String?] = [],
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

    /// A row: a title with an optional detail line, and a value or a checkmark on the right.
    static func row(_ title: String, detail: String? = nil, value: String? = nil, checked: Bool = false,
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

    /// A row that does something that can't be undone (signing out,
    /// deleting), only once the viewer answers the model's `Confirmation`.
    static func confirmedRow(_ confirmation: Confirmation, action: @escaping () -> Void) -> some View {
        ConfirmedRow(confirmation: confirmation, action: action)
    }

    /// A small button in a row of several, such as a day of the week: its
    /// title centred, brighter when `selected`.
    static func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).fontWeight(selected ? .bold : .regular).lineLimit(1)
        }
        .buttonStyle(SettingsRowStyle(compact: true, selected: selected))
    }

    /// A label and its value, not selectable, lined up with the rows.
    static func info(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).font(.title3.monospaced()).bold()
        }
        .padding(.horizontal, SettingsRowStyle.inset)
    }

    /// The dark full-screen page, scrolling, that both screens sit on.
    /// Settings lets the programme show faintly through; the channel editor,
    /// which opens over Settings, is solid.
    static func page(opacity: Double = 0.92, @ViewBuilder content: () -> some View) -> some View {
        // A scroll view of our own rows, not a List: the system's focus
        // highlight in a List left light text on a light background on a TV.
        ScrollView {
            VStack(alignment: .leading, spacing: 56) { content() }
                .frame(maxWidth: 1200)
                .padding(.horizontal, 60)
                .padding(.vertical, 60)
                .frame(maxWidth: .infinity)
        }
        .background(Color.black.opacity(opacity).ignoresSafeArea())
    }
}

/// A settings row. Highlighted, it's white with black text; otherwise white
/// text on a faint row. The colours are set here, not left to the system,
/// so text always stands out from the highlight. (`.secondary` text follows
/// along, as grey on either.)
struct SettingsRowStyle: ButtonStyle {
    static let inset: CGFloat = 32
    /// Centred, with less padding, for `SettingsRows.chip`.
    var compact = false
    /// Chosen: a brighter row when not highlighted.
    var selected = false

    func makeBody(configuration: Configuration) -> some View {
        Row(configuration: configuration, compact: compact, selected: selected)
    }

    private struct Row: View {
        let configuration: ButtonStyleConfiguration
        let compact: Bool
        let selected: Bool
        @Environment(\.isFocused) private var isFocused

        private var resting: Double { configuration.isPressed ? 0.25 : selected ? 0.3 : 0.08 }

        var body: some View {
            configuration.label
                .font(.body)
                .foregroundStyle(configuration.role == .destructive ? Color.red : isFocused ? Color.black : Color.white)
                .frame(maxWidth: .infinity, alignment: compact ? .center : .leading)
                .padding(.horizontal, compact ? 8 : SettingsRowStyle.inset)
                .padding(.vertical, 22)
                .background(isFocused ? Color.white : Color.white.opacity(resting),
                            in: RoundedRectangle(cornerRadius: 16))
                .scaleEffect(isFocused ? 1.02 : 1)
                .shadow(color: .black.opacity(isFocused ? 0.4 : 0), radius: 12, y: 6)
                .animation(.easeOut(duration: 0.15), value: isFocused)
        }
    }
}


/// See `SettingsRows.confirmedRow`.
private struct ConfirmedRow: View {
    let confirmation: Confirmation
    let action: () -> Void
    @State private var asking = false

    var body: some View {
        SettingsRows.row(confirmation.action, role: .destructive) { asking = true }
            .confirming(confirmation, isPresented: $asking, action: action)
    }
}
