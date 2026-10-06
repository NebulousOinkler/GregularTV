import Foundation

/// A song's words, timed to the music (`LyricsSource`): each line from when
/// it's sung, and each word too when the lyrics time them.
public struct SyncedLyrics: Sendable, Equatable {
    public struct Line: Sendable, Equatable {
        /// Seconds into the song.
        public let start: TimeInterval
        public let text: String
        /// Each word's timing, in order; empty when only the line is timed.
        public let words: [Word]

        public init(start: TimeInterval, text: String, words: [Word] = []) {
            self.start = start
            self.text = text
            self.words = words
        }
    }

    /// Part of a line's text, sung from `start` (seconds into the song).
    public struct Word: Sendable, Equatable {
        /// Where it is in the line's `text`, in characters.
        public let range: Range<Int>
        public let start: TimeInterval
        /// When it's over, if the lyrics say.
        public let end: TimeInterval?

        public init(range: Range<Int>, start: TimeInterval, end: TimeInterval? = nil) {
            self.range = range
            self.start = start
            self.end = end
        }
    }

    /// In order of time.
    public let lines: [Line]

    public init(lines: [Line]) {
        self.lines = lines.sorted { $0.start < $1.start }
    }
}
