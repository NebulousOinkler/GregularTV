import Foundation
import GregularCore

/// What the lyrics show at any moment of a song: the line being sung with
/// the one after it below, how much of it is sung, where the bouncing ball
/// is, and the countdown dots before singing starts again. Each front end
/// asks it for `moment(at:)` as the song plays and draws the answer.
///
/// - **Words timed:** the ball lands on each word as it's sung, and the
///   words light up as they go.
/// - **Lines timed:** the ball sits on the line's first word, then hops to
///   the next line's as it starts; the whole line lights up.
/// - **Countdown:** before the first line, and before a line that follows a
///   quiet stretch, dots count the last seconds down.
public struct LyricsTimeline: Sendable, Equatable {
    /// A word the ball can be on: its line, and where it is in the line's text (in characters).
    public struct Spot: Sendable, Equatable {
        public let line: Int
        public let range: Range<Int>
    }

    /// The ball, part way through a hop.
    public struct Ball: Sendable, Equatable {
        public let from: Spot
        /// Where it lands; nil if it stays put (the last word).
        public let to: Spot?
        /// How far through the hop, 0 (on `from`) to 1 (landing on `to`).
        public let progress: Double
    }

    public struct Moment: Sendable, Equatable {
        /// The line on screen being sung (an index into `lines`), if any.
        public let line: Int?
        /// The line shown below it, coming next.
        public let next: Int?
        /// How many of `line`'s characters are sung, part way through the word being sung.
        public let sung: Double
        public let ball: Ball?
        /// Dots left in the countdown (4 to 1), if one's showing.
        public let countdown: Int?
    }

    /// Dots in a countdown, one a second.
    public static let countdownDots = 4
    /// A gap this long since the last thing sung makes the next line count in.
    public static let quietStretch: TimeInterval = 8
    /// How long a line's last word lights up for, when the lyrics don't say.
    public static let lastWordLength: TimeInterval = 1

    public let lines: [SyncedLyrics.Line]

    public init(_ lyrics: SyncedLyrics) {
        lines = lyrics.lines
    }

    public func moment(at time: TimeInterval) -> Moment {
        // The last line that's started; a blank one means a gap.
        let started = lines.lastIndex { $0.start <= time }
        let current = started.flatMap { lines[$0].text.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
        let upcoming = lines.indices.first { lines[$0].start > time && !lines[$0].text.trimmingCharacters(in: .whitespaces).isEmpty }
        return Moment(line: current, next: upcoming, sung: current.map { sung(on: $0, at: time) } ?? 0,
                      ball: ball(current: current, upcoming: upcoming, at: time),
                      countdown: countdown(current: current, upcoming: upcoming, at: time))
    }

    private func sung(on index: Int, at time: TimeInterval) -> Double {
        let line = lines[index]
        guard !line.words.isEmpty else { return Double(line.text.count) }
        guard let word = line.words.lastIndex(where: { $0.start <= time }) else { return 0 }
        let range = line.words[word].range
        let start = line.words[word].start
        let end = line.words[word].end ?? (word + 1 < line.words.count ? line.words[word + 1].start
            : min(start + Self.lastWordLength, nextStart(after: index) ?? .infinity))
        let fraction = end > start ? min(1, (time - start) / (end - start)) : 1
        return Double(range.lowerBound) + Double(range.count) * fraction
    }

    private func ball(current: Int?, upcoming: Int?, at time: TimeInterval) -> Ball? {
        guard let current else { return nil }
        let line = lines[current]
        guard !line.words.isEmpty else {
            // Lines timed: on this line's first word, hopping to the next line's as it starts.
            let from = Spot(line: current, range: firstWord(of: current))
            guard let upcoming else { return Ball(from: from, to: nil, progress: 0) }
            return Ball(from: from, to: Spot(line: upcoming, range: firstWord(of: upcoming)),
                        progress: hop(from: line.start, to: lines[upcoming].start, at: time))
        }
        // Words timed: on each word as it's sung, hopping to the next.
        let word = line.words.lastIndex { $0.start <= time } ?? 0
        let from = Spot(line: current, range: line.words[word].range)
        guard word + 1 < line.words.count else { return Ball(from: from, to: nil, progress: 0) }
        let next = line.words[word + 1]
        return Ball(from: from, to: Spot(line: current, range: next.range), progress: hop(from: line.words[word].start, to: next.start, at: time))
    }

    private func countdown(current: Int?, upcoming: Int?, at time: TimeInterval) -> Int? {
        guard let upcoming else { return nil }
        let start = lines[upcoming].start
        let left = start - time
        guard left > 0, left <= Double(Self.countdownDots) else { return nil }
        // Only after a quiet stretch: nothing sung yet, or the last thing sung long before.
        if let current, start - lastSung(on: current) < Self.quietStretch { return nil }
        return Int(left.rounded(.up))
    }

    /// When the last word (or the line) on `index` started.
    private func lastSung(on index: Int) -> TimeInterval {
        lines[index].words.last?.start ?? lines[index].start
    }

    private func nextStart(after index: Int) -> TimeInterval? {
        index + 1 < lines.count ? lines[index + 1].start : nil
    }

    private func hop(from start: TimeInterval, to end: TimeInterval, at time: TimeInterval) -> Double {
        end > start ? min(1, max(0, (time - start) / (end - start))) : 1
    }

    /// The first word of a line's text, in characters.
    private func firstWord(of index: Int) -> Range<Int> {
        let text = Array(lines[index].text)
        let start = text.firstIndex { !$0.isWhitespace } ?? 0
        let end = text[start...].firstIndex(where: \.isWhitespace) ?? text.count
        return start..<end
    }
}
