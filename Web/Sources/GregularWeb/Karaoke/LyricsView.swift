import Foundation
import GregularCore
import GregularScreens
import JavaScriptKit

/// The lyrics of the song on stage, as `LyricsTimeline` says at each
/// moment: the line being sung, lighting up word by word, the next line
/// below it, the bouncing ball, and the countdown dots.
///
/// Each word is a `<span>` (`data-start` and `data-end`, in characters),
/// filled as it's sung through its `--fill` (0 to 1), rising a touch while
/// it's being sung (`k-singing`); the ball is moved over the words with a
/// transform, squashed (`--squash`) as it lands and leaves. A new line
/// rises into place (`k-enter`). Only `update(at:)` changes anything, once
/// a frame.
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
            current.replaceChildren(moment.line.map { Self.spans(timeline.segments(ofLine: $0)) } ?? [])
            next.replaceChildren(moment.next.map { Self.spans(timeline.segments(ofLine: $0)) } ?? [])
            // Rising into place: the animation starts again on each new line.
            for line in [current, next] {
                line.classed("k-enter", false)
                _ = line.object.offsetWidth
                line.classed("k-enter", true)
            }
        }
        fill(sung: moment.sung)
        let count = moment.countdown ?? 0
        if dots.object.childElementCount.number.map(Int.init) != count {
            dots.replaceChildren((0..<count).map { _ in El("span", "k-dot") })
        }
        place(moment.ball)
    }

    private static func spans(_ segments: [LyricsTimeline.Segment]) -> [El] {
        segments.map { segment in
            El("span", segment.isWord ? "k-word" : "k-gap", text: segment.text)
                .attribute("data-start", String(segment.range.lowerBound)).attribute("data-end", String(segment.range.upperBound))
        }
    }

    /// Lights the current line up to `sung` characters.
    private func fill(sung: Double) {
        let list = current.object.children.object!
        for index in 0..<Int(list.length.number ?? 0) {
            guard let span = list[index].object,
                  let start = span.dataset.start.string.flatMap(Int.init), let end = span.dataset.end.string.flatMap(Int.init)
            else { continue }
            let fill = LyricsTimeline.fill(start..<end, sung: sung)
            _ = span.style.setProperty("--fill", String(fill))
            _ = span.classList.toggle("k-singing", fill > 0 && fill < 1 && end > start)
        }
    }

    /// Puts the ball over its word, part way along an arc to the next.
    private func place(_ ball: LyricsTimeline.Ball?) {
        guard let ball, let from = rect(of: ball.from) else {
            self.ball.hidden = true
            return
        }
        let to = ball.to.flatMap(rect(of:)) ?? from
        let p = ball.to == nil ? 0 : ball.progress
        let x = from.x + (to.x - from.x) * p
        let y = from.y + (to.y - from.y) * p - sin(.pi * p) * Self.bounce * max(from.height, to.height)
        let squash = ball.to == nil ? 0 : max(0, 1 - min(p, 1 - p) / 0.1)
        self.ball.hidden = false
        self.ball.style("transform", "translate(\(x)px, \(y)px)")
        self.ball.style("--squash", String(format: "%.3f", squash))
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
