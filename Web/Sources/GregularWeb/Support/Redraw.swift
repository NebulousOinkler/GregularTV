import Foundation
import JavaScriptKit
import Observation

/// Runs `draw` now, and again whenever anything observable it read changes
/// (a GregularScreens model, a `Clock`), until `stop()`. It's how every page
/// keeps itself up to date: each part of a page has its own, so a change
/// redraws only the parts that read it.
@MainActor final class Redraw {
    private let draw: @MainActor () -> Void
    private var stopped = false
    private var pending = false

    /// Keep it: it stops once it's let go.
    init(_ draw: @escaping @MainActor () -> Void) {
        self.draw = draw
        run()
    }

    func stop() {
        stopped = true
    }

    private func run() {
        guard !stopped else { return }
        pending = false
        withObservationTracking(draw) { [weak self] in
            // Called as the change is about to happen: draw once it has,
            // and only once however many changes come together.
            Task { @MainActor in
                guard let self, !self.pending else { return }
                self.pending = true
                self.run()
            }
        }
    }
}

/// A task started whenever `id` changes, the one before cancelled: what
/// SwiftUI's `.task(id:)` does. For the models' timers (`runBannerTimer()`,
/// `runCurtain()`, `runStationCard()`), keyed by their triggers.
@MainActor final class TaskSlot<ID: Equatable> {
    private var id: ID?
    private var task: Task<Void, Never>?

    func run(for id: ID, _ work: @escaping @MainActor () async -> Void) {
        guard id != self.id else { return }
        self.id = id
        task?.cancel()
        task = Task { await work() }
    }

    func cancel() {
        task?.cancel()
        task = nil
        id = nil
    }
}

/// The time, observable: a page that reads `now` is redrawn as it changes,
/// every `interval`, like SwiftUI's `TimelineView`.
@MainActor @Observable final class Clock {
    private(set) var now = Date.now
    @ObservationIgnored private var timer: JSValue = .undefined
    @ObservationIgnored private var tick: JSClosure?

    init(every interval: TimeInterval) {
        let tick = JSClosure { [weak self] _ in
            MainActor.assumeIsolated { self?.now = .now }
            return .undefined
        }
        self.tick = tick
        timer = JSObject.global.setInterval!(tick, interval * 1000)
    }

    func stop() {
        _ = JSObject.global.clearInterval!(timer)
        tick = nil
    }
}
