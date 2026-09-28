import GregularCore
import GregularScreens
import SwiftUI

/// Making or editing a custom channel, from Settings › Channels. Draws a
/// `ChannelEditorModel`: the choices come from the library in memory, and
/// the preview shows what would air, all without asking the server.
struct ChannelEditorView: View {
    @Bindable var model: ChannelEditorModel
    let onSave: (CustomChannel) -> Void
    let onDelete: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var choosingProgramme = false
    @State private var setTimeError: String?

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

            setTimes

            preview

            SettingsRows.section(nil, footer: [model.problem]) {
                SettingsRows.row("Save") {
                    guard model.problem == nil, let channel = model.channel else { return }
                    dismiss()
                    onSave(channel)
                }
                .disabled(model.problem != nil)
                if let onDelete {
                    SettingsRows.row("Delete Channel", role: .destructive) {
                        dismiss()
                        onDelete()
                    }
                }
                SettingsRows.row("Cancel") { dismiss() }
            }
        }
    }

    /// The list to pick from, for the kind of rule chosen.
    @ViewBuilder private var ruleChoices: some View {
        switch model.ruleKind {
        case .everything:
            EmptyView()
        case .genre:
            choices("Genre", model.genres, selected: $model.genre)
        case .series:
            choices("Series", model.seriesNames, selected: $model.series)
        case .tag:
            choices("Tag", model.tags, selected: $model.tag)
        case .years:
            SettingsRows.section("Years", footer: [model.years.map { "Your library runs from \($0.lowerBound) to \($0.upperBound). Leave one blank to leave it open." }]) {
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

    /// Programmes at set times: the ones set, and a form to add another.
    @ViewBuilder private var setTimes: some View {
        SettingsRows.section("Set times", footer: [
            "Programmes here air at exactly these times every day (or on the days chosen), in this Apple TV's time zone, \(model.timeZone.identifier). The shuffle fills the time around them.",
        ]) {
            ForEach(model.fixed, id: \.self) { entry in
                SettingsRows.row(entry.match.title, detail: entry.summary, value: "Remove") { model.removeFixed(entry) }
            }
        }
        SettingsRows.section("Add a set time", footer: [setTimeError]) {
            SettingsRows.row(model.draftProgramme?.title ?? "Choose a series or film",
                             value: choosingProgramme ? "Done" : "Choose") { choosingProgramme.toggle() }
            if choosingProgramme {
                ForEach(model.seriesNames, id: \.self) { name in draftChoice(.series(name)) }
                ForEach(model.movieNames, id: \.self) { name in draftChoice(.item(name)) }
            }
            TextField("Times, like 18:00 or 18:00, 18:30", text: $model.draftTimes)
                .autocorrectionDisabled()
            HStack(spacing: 12) {
                ForEach(1...7, id: \.self) { weekday in
                    SettingsRows.chip(FixedProgramme.weekdayName(weekday), selected: model.draftWeekdays.contains(weekday)) {
                        if model.draftWeekdays.remove(weekday) == nil { model.draftWeekdays.insert(weekday) }
                    }
                }
            }
            Text("No days chosen means every day.").font(.caption).foregroundStyle(.secondary)
                .padding(.horizontal, SettingsRowStyle.inset)
            SettingsRows.row("Only at these times", detail: "Keeps it out of the shuffle",
                             value: model.draftExclusive ? "On" : "Off") { model.draftExclusive.toggle() }
            SettingsRows.row("Add Set Time") {
                setTimeError = model.addDraft()
                if setTimeError == nil { choosingProgramme = false }
            }
        }
    }

    private func draftChoice(_ match: FixedProgramme.Match) -> some View {
        SettingsRows.row(match.title, checked: model.draftProgramme == match) {
            model.draftProgramme = match
            choosingProgramme = false
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
                    Text(entry.start.clockTime).monospacedDigit().foregroundStyle(.secondary)
                    Text(entry.title).lineLimit(1)
                }
                .padding(.horizontal, SettingsRowStyle.inset)
            }
        }
    }
}
