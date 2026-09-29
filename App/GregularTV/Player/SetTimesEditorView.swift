import GregularCore
import GregularScreens
import SwiftUI

/// Setting programmes at fixed times on one channel, from Settings › Set
/// times. Draws a `SetTimesEditorModel`: the choices come from the library in
/// memory, and the preview shows when they'll air, all without asking the server.
struct SetTimesEditorView: View {
    @Bindable var model: SetTimesEditorModel
    let onSave: (SetTimes) -> Void
    let onDelete: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var choosingProgramme = false
    @State private var draftError: String?

    var body: some View {
        SettingsRows.page(opacity: 1) {
            Text("Set Times on \(model.channelNumber)  \(model.channelName)").font(.largeTitle).bold()

            SettingsRows.section("Set times", footer: [
                model.programmes.isEmpty ? "None yet: add one below." : nil,
                "These air at exactly these times, in \(model.isInLocalTimeZone ? "this Apple TV's time zone" : "the time zone they were set in") (\(model.timeZone.identifier)). The rest of the time, the channel is the same as for everyone with your schedule code.",
            ]) {
                ForEach(model.programmes, id: \.self) { entry in
                    SettingsRows.row(entry.match.title,
                                     detail: model.isMissing(entry) ? "\(entry.summary) · Not in your library, so it won't air" : entry.summary,
                                     value: "Remove") { model.remove(entry) }
                }
            }

            addSetTime

            preview

            SettingsRows.section(nil, footer: [model.programmes.isEmpty ? nil : model.problem]) {
                SettingsRows.row("Save") {
                    guard model.problem == nil else { return }
                    dismiss()
                    onSave(model.setTimes)
                }
                .disabled(model.problem != nil)
                if let onDelete {
                    SettingsRows.confirmedRow("Delete Set Times", asking: "Delete the set times on channel \(model.channelNumber)?",
                                              detail: "The channel goes back to the shared schedule. To get them back, you'd need their set-times code.") {
                        dismiss()
                        onDelete()
                    }
                }
                SettingsRows.row("Cancel") { dismiss() }
            }
        }
        #if DEBUG
        .debugMenuKeyCloses()
        #endif
    }

    /// A form to add another set time.
    @ViewBuilder private var addSetTime: some View {
        SettingsRows.section("Add a set time", footer: [draftError]) {
            SettingsRows.row(model.draftProgramme?.title ?? "Choose a series or film",
                             value: choosingProgramme ? "Done" : "Choose") { choosingProgramme.toggle() }
            if choosingProgramme {
                ForEach(model.choices.seriesNames, id: \.self) { name in draftChoice(.series(name)) }
                ForEach(model.choices.movieNames, id: \.self) { name in draftChoice(.item(name)) }
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
            SettingsRows.row("Only at these times", detail: "Anywhere else it would air on this channel, something else does",
                             value: model.draftExclusive ? "On" : "Off") { model.draftExclusive.toggle() }
            SettingsRows.row("Add Set Time") {
                draftError = model.addDraft()
                if draftError == nil { choosingProgramme = false }
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
        let upcoming = model.programmes.isEmpty ? [] : model.upcoming()
        return SettingsRows.section("Coming up", footer: [
            model.programmes.isEmpty ? nil : "Set-times code: \(model.setTimes.code). Type it into another Apple TV's Settings to watch the same set times there.",
        ]) {
            if upcoming.isEmpty { SettingsRows.info("Next two days", "Nothing set") }
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
