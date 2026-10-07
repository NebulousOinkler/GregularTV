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

    /// Part of a line as drawn: a word, or what's between words.
    public struct Segment: Sendable, Equatable, Identifiable {
        /// Where it is in the line's text, in characters.
        public let range: Range<Int>
        public let text: String
        public let isWord: Bool
        public var id: Int { range.lowerBound }

        /// How much of it is lit (0 to 1), with `sung` characters of its line sung.
        public func fill(sung: Double) -> Double {
            LyricsTimeline.fill(range, sung: sung)
        }
    }

    /// How much of the characters in `range` are lit (0 to 1), with `sung` characters of their line sung.
    public static func fill(_ range: Range<Int>, sung: Double) -> Double {
        range.isEmpty ? 1 : min(1, max(0, (sung - Double(range.lowerBound)) / Double(range.count)))
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

    /// How long a pulse takes to die away, in seconds.
    public static let pulseLength: TimeInterval = 0.2

    /// A beat for the backdrop to pulse to (1 as a word, or a line, starts;
    /// dying away to 0): the lyrics' timings stand in for the song's beat,
    /// which the app never analyses.
    public func pulse(at time: TimeInterval) -> Double {
        guard let index = lines.lastIndex(where: { $0.start <= time }),
              !lines[index].text.trimmingCharacters(in: .whitespaces).isEmpty else { return 0 }
        let started = lines[index].words.last(where: { $0.start <= time })?.start ?? lines[index].start
        return exp(-(time - started) / Self.pulseLength)
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
        segments(ofLine: index).first(where: \.isWord)?.range ?? 0..<0
    }

    /// A line's text as words and the gaps between, in order: its timed
    /// words, or without timings, whatever's between spaces. The ball's
    /// spots are its words.
    public func segments(ofLine index: Int) -> [Segment] {
        let line = lines[index]
        let characters = Array(line.text)
        let words = line.words.isEmpty ? Self.spaced(characters) : line.words.map(\.range).sorted { $0.lowerBound < $1.lowerBound }
        var segments: [Segment] = []
        var at = 0
        func add(_ range: Range<Int>, word: Bool) {
            guard !range.isEmpty else { return }
            segments.append(Segment(range: range, text: String(characters[range]), isWord: word))
        }
        for word in words where word.lowerBound >= at && word.upperBound <= characters.count {
            add(at..<word.lowerBound, word: false)
            add(word, word: true)
            at = word.upperBound
        }
        add(at..<characters.count, word: false)
        return segments
    }

    private static func spaced(_ characters: [Character]) -> [Range<Int>] {
        var words: [Range<Int>] = []
        var start: Int?
        for (index, character) in characters.enumerated() {
            if character.isWhitespace {
                if let begun = start { words.append(begun..<index) }
                start = nil
            } else if start == nil {
                start = index
            }
        }
        if let begun = start { words.append(begun..<characters.count) }
        return words
    }
}
