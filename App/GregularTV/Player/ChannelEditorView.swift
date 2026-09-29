import GregularCore
import GregularScreens
import SwiftUI

/// Making or editing a custom channel, from Settings › Your channels. Draws a
/// `ChannelEditorModel`: the choices come from the library in memory, and
/// the preview shows what would air, all without asking the server.
struct ChannelEditorView: View {
    @Bindable var model: ChannelEditorModel
    let onSave: (CustomChannel) -> Void
    let onDelete: (() -> Void)?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SettingsRows.page(opacity: 1) {
            Text(model.original == nil ? "New Channel" : "Edit Channel").font(.largeTitle).bold()

            SettingsRows.section("Name") {
                TextField("Channel name", text: $model.name)
                    .autocorrectionDisabled()
            }

            SettingsRows.section("Number", footer: ["Custom channels use 20 to 99. Taken numbers are skipped."]) {
                HStack(spacing: 24) {
                    SettingsRows.row("Lower") { model.stepNumber(by: -1) }
                    Text("\(model.number)").font(.title2.monospacedDigit()).bold().frame(minWidth: 120)
                    SettingsRows.row("Higher") { model.stepNumber(by: 1) }
                }
            }

            SettingsRows.section("Plays") {
                ForEach(ChannelEditorModel.Content.allCases, id: \.self) { content in
                    SettingsRows.row(content.label, checked: model.content == content) { model.content = content }
                }
            }

            SettingsRows.section("Which programmes") {
                ForEach(ChannelEditorModel.RuleKind.allCases, id: \.self) { kind in
                    SettingsRows.row(kind.label, checked: model.ruleKind == kind) { model.ruleKind = kind }
                }
            }
            ruleChoices

            SettingsRows.section("Schedule", footer: [
                "Half-hour slots start every programme on the hour or half hour, with a break before the next.",
            ]) {
                SettingsRows.row("Half-hour slots", value: model.halfHourSlots ? "On" : "Off") { model.halfHourSlots.toggle() }
                SettingsRows.row("Commercials in breaks", value: model.commercials ? "On" : "Off") { model.commercials.toggle() }
            }

            preview

            SettingsRows.section(nil, footer: [model.problem]) {
                SettingsRows.row("Save") {
                    guard model.problem == nil, let channel = model.channel else { return }
                    dismiss()
                    onSave(channel)
                }
                .disabled(model.problem != nil)
                if let onDelete {
                    SettingsRows.confirmedRow(model.deleteConfirmation) {
                        dismiss()
                        onDelete()
                    }
                }
                SettingsRows.row("Cancel") { dismiss() }
            }
        }
        .debugMenuKeyCloses()
    }

    /// The list to pick from, for the kind of rule chosen.
    @ViewBuilder private var ruleChoices: some View {
        switch model.ruleKind {
        case .everything:
            EmptyView()
        case .genre:
            choices("Genre", model.choices.genres, selected: $model.genre)
        case .series:
            choices("Series", model.choices.seriesNames, selected: $model.series)
        case .tag:
            choices("Tag", model.choices.tags, selected: $model.tag)
        case .years:
            SettingsRows.section("Years", footer: [model.choices.years.map { "Your library runs from \($0.lowerBound) to \($0.upperBound). Leave one blank to leave it open." }]) {
                TextField("From (any year)", value: $model.fromYear, format: .number.grouping(.never))
                TextField("To (any year)", value: $model.toYear, format: .number.grouping(.never))
            }
        }
    }

    private func choices(_ title: String, _ names: [String], selected: Binding<String?>) -> some View {
        SettingsRows.section(title, footer: [names.isEmpty ? "There are none in your library." : nil]) {
            ForEach(names, id: \.self) { name in
                SettingsRows.row(name, checked: selected.wrappedValue == name) { selected.wrappedValue = name }
            }
        }
    }

    private var preview: some View {
        let upcoming = model.upcoming()
        return SettingsRows.section("Preview", footer: [
            model.channel.map { "Channel code: \($0.code). Type it into another Apple TV's Settings to add this channel there." },
        ]) {
            SettingsRows.info("Programmes that match", "\(model.matchingCount)")
            ForEach(upcoming) { entry in
                HStack(spacing: 24) {
                    Text(entry.when).monospacedDigit().foregroundStyle(.secondary)
                    Text(entry.title).lineLimit(1)
                }
                .padding(.horizontal, SettingsRowStyle.inset)
            }
        }
    }
}
