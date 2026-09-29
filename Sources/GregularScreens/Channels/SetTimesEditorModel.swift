import Foundation
import GregularCore
import Observation

/// Setting programmes at fixed times on one channel (Settings › Set times).
/// They're laid over the channel's shared schedule, so everyone with the
/// same schedule code still sees the same programmes at every other time.
/// The times are read in this Apple TV's time zone, kept with them. Nothing
/// is saved until `AppModel.save(_:replacing:)`.
@MainActor @Observable
public final class SetTimesEditorModel {
    public let channelNumber: Int
    public let channelName: String
    public private(set) var programmes: [FixedProgramme]
    public let timeZone: TimeZone

    /// A set time being added: what (a series or a film), when ("18:00,
    /// 18:30"), on which weekdays (none means every day), and whether its
    /// other airings on the channel get a stand-in.
    public var draftProgramme: FixedProgramme.Match?
    public var draftTimes = ""
    public var draftWeekdays = Set<Int>()
    public var draftExclusive = false

    /// The set times being edited, or nil for new ones.
    public let original: SetTimes?
    /// The library's series and films, to pick from.
    public let choices: LibraryChoices

    private let library: [MediaItem]
    /// The line-up without this household's set times on the channel.
    private let lineup: ChannelLineup
    private let code: ScheduleCode

    /// - Parameters:
    ///   - channel: the channel they're on, from `lineup`.
    ///   - lineup: the line-up without the set times being edited.
    ///   - code: the schedule code, so the preview matches what will air.
    public init(channel: Channel, editing original: SetTimes?, library: [MediaItem], lineup: ChannelLineup,
                code: ScheduleCode, timeZone: TimeZone = .current) {
        channelNumber = channel.number
        channelName = channel.name
        self.original = original
        programmes = original?.programmes ?? []
        self.timeZone = original?.timeZone ?? timeZone
        self.library = library
        self.lineup = lineup
        self.code = code
        choices = LibraryChoices(library)
    }

    /// The set times as they stand.
    public var setTimes: SetTimes {
        SetTimes(channelNumber: channelNumber, programmes: programmes, timeZone: timeZone)
    }

    /// Adds the draft set time. Returns why it can't be added, or nil.
    @discardableResult
    public func addDraft() -> String? {
        guard let match = draftProgramme else { return "Choose a series or film to set at a time." }
        let parts = draftTimes.split(whereSeparator: { $0 == "," || $0 == " " })
        let times = parts.compactMap { FixedProgramme.minutes(from: String($0)) }
        guard !times.isEmpty, times.count == parts.count else {
            return "Enter times like 18:00, or several like 18:00, 18:30."
        }
        let entry = FixedProgramme(match: match, times: times, weekdays: draftWeekdays, exclusive: draftExclusive,
                                   timeZone: timeZone)
        if let clash = entry.clashes(with: programmes).first {
            return "Something else is already set at \(FixedProgramme.text(forMinutes: clash))."
        }
        programmes.append(entry)
        draftProgramme = nil
        draftTimes = ""
        draftWeekdays = []
        draftExclusive = false
        return nil
    }

    public func remove(_ entry: FixedProgramme) {
        programmes.removeAll { $0 == entry }
    }

    /// Why they can't be saved yet, in plain words, or nil if they can.
    public var problem: String? {
        guard !programmes.isEmpty else { return "Add a set time first." }
        do {
            _ = try lineup.adding([], setTimes: [setTimes])
        } catch {
            return "\(error)"
        }
        return nil
    }

    /// The next set airings, over the next `days`.
    public func upcoming(from now: Date = .now, days: Double = 2) -> [UpcomingProgramme] {
        guard let channel = try? lineup.adding([], setTimes: [setTimes]).channels.first(where: { $0.number == channelNumber }),
              let schedule = ChannelSchedule(channel: channel, items: library, code: code)
        else { return [] }
        return schedule.setTimeAirings(from: now, to: now.addingTimeInterval(days * 24 * 3600)).map(UpcomingProgramme.init)
    }
}
