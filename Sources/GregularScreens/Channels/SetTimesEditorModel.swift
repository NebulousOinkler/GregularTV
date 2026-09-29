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

    /// A set time being added: what (a series or a film), when ("6:00 PM,
    /// 6:30 PM", or "18:00, 18:30"), on which weekdays (none means every day), and whether its
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

    /// Whether the times are read in this device's own time zone. Set times
    /// shared from another zone keep theirs.
    public var isInLocalTimeZone: Bool { timeZone == .current }

    /// The set times as they stand.
    public var setTimes: SetTimes {
        SetTimes(channelNumber: channelNumber, programmes: programmes, timeZone: timeZone)
    }

    /// Adds the draft set time. Returns why it can't be added, or nil.
    @discardableResult
    public func addDraft() -> String? {
        guard let match = draftProgramme else { return "Choose a series or film to set at a time." }
        guard let times = FixedProgramme.typedTimes(draftTimes) else {
            return "Enter times like \(Self.example(1)), or several like \(Self.example(2))."
        }
        guard programmes.count < FixedProgramme.mostPerChannel else {
            return "A channel can have at most \(FixedProgramme.mostPerChannel) set times."
        }
        guard programmes.reduce(times.count, { $0 + $1.times.count }) <= FixedProgramme.mostTimesPerChannel else {
            return "A channel's set times can list at most \(FixedProgramme.mostTimesPerChannel) times in all."
        }
        let entry = FixedProgramme(match: match, times: times, weekdays: draftWeekdays, exclusive: draftExclusive,
                                   timeZone: timeZone)
        if let clash = entry.clashes(with: programmes).first {
            return "Something else is already set at \(FixedProgramme.clockText(forMinutes: clash))."
        }
        programmes.append(entry)
        draftProgramme = nil
        draftTimes = ""
        draftWeekdays = []
        draftExclusive = false
        return nil
    }

    /// The times field's prompt, in the viewer's clock format: "Times, like
    /// 6:00 PM or 6:00 PM, 6:30 PM".
    public static var timesPrompt: String {
        "Times, like \(example(1)) or \(example(2))"
    }

    /// One or two example times, 6:00 PM and 6:30 PM, as the viewer's clock shows them.
    static func example(_ count: Int) -> String {
        [1080, 1110].prefix(count).map { FixedProgramme.clockText(forMinutes: $0) }.joined(separator: ", ")
    }

    /// True when the library has nothing `entry` names, so it never airs
    /// here (set with another library, and shared by code).
    public func isMissing(_ entry: FixedProgramme) -> Bool {
        !entry.isAvailable(in: library)
    }

    public func remove(_ entry: FixedProgramme) {
        programmes.removeAll { $0 == entry }
    }

    /// Ask this before deleting the set times being edited.
    public var deleteConfirmation: Confirmation {
        Confirmation(action: "Delete Set Times", question: "Delete the set times on channel \(channelNumber)?",
                     detail: "The channel goes back to the shared schedule. To get them back, you'd need their set-times code.")
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
        return schedule.setTimeAirings(from: now, to: now.addingTimeInterval(days * 24 * 3600)).map { UpcomingProgramme($0, now: now) }
    }
}
