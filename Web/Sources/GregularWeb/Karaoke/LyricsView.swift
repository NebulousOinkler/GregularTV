import Foundation
import GregularCore
import GregularScreens
import JavaScriptKit

/// The lyrics of the song on stage, as `LyricsTimeline` says at each
/// moment: the line being sung, lighting up word by word, the next line
/// below it, the bouncing ball, and the countdown dots.
///
/// Each word is a `<span>` (`data-start` and `data-end`, in characters),
/// filled as it's sung through its `--fill` (0 to 1); the ball is moved
/// over the words with a transform. Only `update(at:)` changes anything,
/// once a frame.
@MainActor final class LyricsView {
    let element = El("div", "k-lyrics")
    private let dots = El("p", "k-dots").attribute("aria-hidden", "true")
    private let current = El("p", "k-line k-line-current")
    private let next = El("p", "k-line k-line-next")
    private let ball = El("span", "k-ball").attribute("aria-hidden", "true")
    private var timeline: LyricsTimeline?
    private var shown: (line: Int?, next: Int?) = (nil, nil)
    /// How high the ball bounces between words, as a share of a line's height.
    private static let bounce = 0.7

    init() {
        element.append(dots, current, next, ball)
        element.hidden = true
    }

    func show(_ timeline: LyricsTimeline?) {
        guard timeline != self.timeline else { return }
        self.timeline = timeline
        shown = (nil, nil)
        current.replaceChildren([])
        next.replaceChildren([])
        element.hidden = timeline == nil
    }

    func update(at time: TimeInterval) {
        guard let timeline else { return }
        let moment = timeline.moment(at: time)
        if moment.line != shown.line || moment.next != shown.next {
            shown = (moment.line, moment.next)
            current.replaceChildren(moment.line.map { Self.spans(timeline.lines[$0]) } ?? [])
            next.replaceChildren(moment.next.map { Self.spans(timeline.lines[$0]) } ?? [])
        }
        fill(sung: moment.sung)
        dots.text = moment.countdown.map { String(repeating: "\u{25CF}", count: $0) } ?? ""
        place(moment.ball)
    }

    /// The line's text as words and the gaps between them. Without word
    /// timings, the words are whatever's between spaces.
    private static func spans(_ line: SyncedLyrics.Line) -> [El] {
        let characters = Array(line.text)
        let words = line.words.isEmpty ? spaced(characters) : line.words.map(\.range).sorted { $0.lowerBound < $1.lowerBound }
        var spans: [El] = []
        var at = 0
        func add(_ range: Range<Int>, word: Bool) {
            guard !range.isEmpty else { return }
            let span = El("span", word ? "k-word" : "k-gap", text: String(characters[range]))
            span.attribute("data-start", String(range.lowerBound)).attribute("data-end", String(range.upperBound))
            spans.append(span)
        }
        for word in words where word.lowerBound >= at && word.upperBound <= characters.count {
            add(at..<word.lowerBound, word: false)
            add(word, word: true)
            at = word.upperBound
        }
        add(at..<characters.count, word: false)
        return spans
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

    /// Lights the current line up to `sung` characters.
    private func fill(sung: Double) {
        let list = current.object.children.object!
        for index in 0..<Int(list.length.number ?? 0) {
            guard let span = list[index].object,
                  let start = span.dataset.start.string.flatMap(Double.init), let end = span.dataset.end.string.flatMap(Double.init)
            else { continue }
            let fraction = end > start ? min(1, max(0, (sung - start) / (end - start))) : 1
            _ = span.style.setProperty("--fill", String(fraction))
        }
    }

    /// Puts the ball over its word, part way along an arc to the next.
    private func place(_ ball: LyricsTimeline.Ball?) {
        guard let ball, let from = rect(of: ball.from) else {
            self.ball.hidden = true
            return
        }
        let to = ball.to.flatMap(rect(of:)) ?? from
        let p = ball.progress
        let x = from.x + (to.x - from.x) * p
        let y = from.y + (to.y - from.y) * p - sin(.pi * p) * Self.bounce * max(from.height, to.height)
        self.ball.hidden = false
        self.ball.style("transform", "translate(\(x)px, \(y)px)")
    }

    /// Where a word is: the middle of its top, from the top left of the lyrics.
    private func rect(of spot: LyricsTimeline.Spot) -> (x: Double, y: Double, height: Double)? {
        let line = spot.line == shown.line ? current : spot.line == shown.next ? next : nil
        guard let span = line?.object.querySelector!("[data-start=\"\(spot.range.lowerBound)\"]").object else { return nil }
        let box = span.getBoundingClientRect!().object!
        let origin = element.object.getBoundingClientRect!().object!
        let left = (box.left.number ?? 0) - (origin.left.number ?? 0)
        let width = box.width.number ?? 0
        return (left + width / 2, (box.top.number ?? 0) - (origin.top.number ?? 0), box.height.number ?? 0)
    }
}
