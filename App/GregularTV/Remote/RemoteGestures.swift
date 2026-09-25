import SwiftUI
import UIKit

/// While watching, tells the Siri Remote's edge clicks, swipes and light
/// touches apart, and sends whichever are in `map` to `perform`.
///
/// SwiftUI reports a click on the edge of the pad and a swipe across it as
/// the same arrow (`onMoveCommand`), and doesn't see light touches at all. So
/// this attaches UIKit recognizers to the window while the view is on screen:
/// - edge clicks: taps of the arrow press types;
/// - swipes: swipe recognizers for indirect (remote) touches;
/// - a light touch: a tap of an indirect touch, ignored if an edge click came
///   with it (clicking the edge also touches the pad).
/// Clicks in the centre, Play/Pause and Menu stay with SwiftUI.
struct RemoteGestures: UIViewRepresentable {
    let map: [RemoteButton: RemoteAction]
    /// Everything's ignored while false, for example with the guide open.
    let isEnabled: Bool
    let perform: (RemoteAction) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WindowWatcher {
        let view = WindowWatcher()
        view.isUserInteractionEnabled = false
        view.coordinator = context.coordinator
        return view
    }

    func updateUIView(_ view: WindowWatcher, context: Context) {
        context.coordinator.map = map
        context.coordinator.perform = perform
        context.coordinator.setEnabled(isEnabled)
    }

    static func dismantleUIView(_ view: WindowWatcher, coordinator: Coordinator) {
        coordinator.detach()
    }

    @MainActor final class Coordinator: NSObject {
        var map: [RemoteButton: RemoteAction] = [:]
        var perform: (RemoteAction) -> Void = { _ in }
        private var isEnabled = true
        private var recognizers: [UIGestureRecognizer] = []
        private var buttons: [ObjectIdentifier: RemoteButton] = [:]
        /// When an edge click last came, so the touch that came with it isn't also a light touch.
        private var lastEdgeClick = Date.distantPast
        /// A light touch waits this long for an edge click that came with it.
        static let touchSettleTime: Duration = .milliseconds(200)
        static let clickTouchOverlap: TimeInterval = 0.5

        func attach(to window: UIWindow) {
            guard recognizers.isEmpty else { return }
            let clicks: [(RemoteButton, UIPress.PressType)] = [
                (.clickUp, .upArrow), (.clickDown, .downArrow), (.clickLeft, .leftArrow), (.clickRight, .rightArrow),
            ]
            for (button, press) in clicks {
                let tap = UITapGestureRecognizer(target: self, action: #selector(edgeClicked(_:)))
                tap.allowedPressTypes = [NSNumber(value: press.rawValue)]
                tap.allowedTouchTypes = []
                add(tap, as: button, to: window)
            }
            let swipes: [(RemoteButton, UISwipeGestureRecognizer.Direction)] = [
                (.swipeUp, .up), (.swipeDown, .down), (.swipeLeft, .left), (.swipeRight, .right),
            ]
            for (button, direction) in swipes {
                let swipe = UISwipeGestureRecognizer(target: self, action: #selector(swiped(_:)))
                swipe.direction = direction
                swipe.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.indirect.rawValue)]
                add(swipe, as: button, to: window)
            }
            let touch = UITapGestureRecognizer(target: self, action: #selector(touched))
            touch.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.indirect.rawValue)]
            touch.allowedPressTypes = []   // clicks stay with SwiftUI
            add(touch, as: .touchTap, to: window)
            setEnabled(isEnabled)
        }

        private func add(_ recognizer: UIGestureRecognizer, as button: RemoteButton, to window: UIWindow) {
            recognizer.cancelsTouchesInView = false
            window.addGestureRecognizer(recognizer)
            recognizers.append(recognizer)
            buttons[ObjectIdentifier(recognizer)] = button
        }

        func setEnabled(_ enabled: Bool) {
            isEnabled = enabled
            // Off, not just ignored: with the list or guide open, swipes must reach the focus engine.
            for recognizer in recognizers { recognizer.isEnabled = enabled }
        }

        func detach() {
            for recognizer in recognizers { recognizer.view?.removeGestureRecognizer(recognizer) }
            recognizers = []
            buttons = [:]
        }

        private func fire(_ recognizer: UIGestureRecognizer) {
            guard isEnabled, let button = buttons[ObjectIdentifier(recognizer)], let action = map[button] else { return }
            perform(action)
        }

        @objc private func edgeClicked(_ recognizer: UIGestureRecognizer) {
            lastEdgeClick = .now
            fire(recognizer)
        }

        @objc private func swiped(_ recognizer: UIGestureRecognizer) {
            fire(recognizer)
        }

        @objc private func touched(_ recognizer: UIGestureRecognizer) {
            Task { @MainActor in
                try? await Task.sleep(for: Self.touchSettleTime)
                guard Date.now.timeIntervalSince(self.lastEdgeClick) > Self.clickTouchOverlap else { return }
                self.fire(recognizer)
            }
        }
    }

    /// Attaches the recognizers once the view is in a window, and removes them when it leaves.
    final class WindowWatcher: UIView {
        weak var coordinator: Coordinator?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if let window { coordinator?.attach(to: window) } else { coordinator?.detach() }
        }
    }
}
