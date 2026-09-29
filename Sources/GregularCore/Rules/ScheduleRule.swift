import Foundation

/// A special rule the schedule follows on top of every channel's strategy and
/// filler. Strategies decide the order; rules are the few things that must
/// hold whatever the strategy, such as never airing the same movie twice in a
/// row, or airing a programme at a set time.
///
/// Every rule is in `ScheduleRules.all`, and each is one of these kinds,
/// which says where it applies:
/// - `SequenceRule`: what may air straight after what.
/// - `PinRule`: programmes at set times, laid over the shared schedule.
/// - `CoverRule`: which of the shared schedule's airings set times cover
///   with a stand-in.
/// - `ChannelRule`: checks a channel's definition when a line-up is built.
/// - `LineupRule`: checks custom channels and set times against the line-up.
///
/// **To add a rule:** create a type conforming to one of those protocols in
/// `Rules/`, and add it to `ScheduleRules.all`. The engine and the line-up
/// ask the registry for the rules of each kind, so nothing else changes.
public protocol ScheduleRule: Sendable {
    /// Stable identifier, e.g. `"no-programme-twice-in-a-row"`.
    static var id: String { get }
    /// What the rule guarantees, in one sentence.
    static var summary: String { get }

    init()
}

/// Every special rule, in one place.
public enum ScheduleRules {
    public static var all: [any ScheduleRule.Type] {
        [
            NoProgrammeTwiceInARow.self,
            NoCommercialTwiceInARow.self,
            PinnedProgrammes.self,
            ExclusiveProgrammesOnlyAtSetTimes.self,
            FixedTimesAreValid.self,
            CustomChannelNumbers.self,
            SetTimesNeedTheirChannel.self,
            // ← add new rules here
        ]
    }

    /// The rules of one kind, such as `rules(of: (any SequenceRule).self)`.
    public static func rules<Kind>(of kind: Kind.Type) -> [Kind] {
        all.compactMap { $0.init() as? Kind }
    }

    /// The sequence rules for one stream.
    static func sequenceRules(for stream: ScheduleStream) -> [any SequenceRule] {
        rules(of: (any SequenceRule).self).filter { type(of: $0).stream == stream }
    }
}

extension [any SequenceRule] {
    /// Whether every rule lets `next` air straight after `previous`.
    func allow(_ next: MediaItem, after previous: MediaItem) -> Bool {
        allSatisfy { $0.allows(next, after: previous) }
    }
}

// MARK: - Kinds of rule

/// Which stream a `SequenceRule` checks.
public enum ScheduleStream: Sendable {
    case programmes
    case commercials
}

/// Decides what may air straight after what. When an item isn't allowed next,
/// it waits and airs as soon as it is, so nothing is lost (see `RuledStream`).
public protocol SequenceRule: ScheduleRule {
    static var stream: ScheduleStream { get }

    /// False when `next` mustn't air straight after `previous`.
    func allows(_ next: MediaItem, after previous: MediaItem) -> Bool
}

/// Decides which airings of the shared schedule a channel's set times cover:
/// each is swapped for a stand-in that fits its slot, and nothing else moves.
public protocol CoverRule: ScheduleRule {
    func covers(_ item: MediaItem, on channel: Channel) -> Bool
}

/// A programme at a set time.
public struct Pin: Sendable, Equatable {
    public let item: MediaItem
    public let start: Date
}

/// One local day, in a set time's time zone.
public struct ScheduleDay: Sendable {
    /// Days since the local day the channel's clock starts in.
    public let index: Int
    /// Its local midnight.
    public let start: Date
    /// In the set time's `timeZone`.
    public let calendar: Calendar
    /// The local day the channel's clock starts in.
    public let firstDay: Date
}

/// Places a set time's programmes, laid over the shared schedule.
public protocol PinRule: ScheduleRule {
    /// Where `entry` airs on `day`, from `programmes`, what it can play (see
    /// `FixedProgramme.programmes(in:)`).
    func pins(for entry: FixedProgramme, programmes: [MediaItem], on day: ScheduleDay) -> [Pin]
}

/// Checks one channel's definition. Any problem stops the line-up loading.
public protocol ChannelRule: ScheduleRule {
    func problems(with channel: Channel) -> [String]
}

/// What a `LineupRule` checks: the bundled channels, and what the viewer added.
public struct LineupAdditions: Sendable {
    public let bundled: [Channel]
    public let custom: [Channel]
    public let setTimes: [SetTimes]
}

/// Checks custom channels and set times against the line-up.
public protocol LineupRule: ScheduleRule {
    func problems(with additions: LineupAdditions) -> [String]
}
