import SwiftUI
import UIKit

/// Calls `action` on a light tap on the Siri Remote's touch surface: a
/// touch, not a click. That's how Apple's own video apps bring up playback info.
///
/// SwiftUI only sees clicks (Select), so this attaches a UIKit tap recognizer
/// for indirect (remote) touches to the window while the view is on screen.
/// It doesn't cancel other touches, so swipes still move focus as usual.
struct RemoteSurfaceTap: UIViewRepresentable {
    /// Taps are ignored while false, for example with the guide open.
    let isEnabled: Bool
    let action: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WindowWatcher {
        let view = WindowWatcher()
        view.isUserInteractionEnabled = false
        view.coordinator = context.coordinator
        return view
    }

    func updateUIView(_ view: WindowWatcher, context: Context) {
        context.coordinator.isEnabled = isEnabled
        context.coordinator.action = action
    }

    static func dismantleUIView(_ view: WindowWatcher, coordinator: Coordinator) {
        coordinator.detach()
    }

    @MainActor final class Coordinator: NSObject {
        var isEnabled = true
        var action: () -> Void = {}
        private var recognizer: UITapGestureRecognizer?

        func attach(to window: UIWindow) {
            guard recognizer == nil else { return }
            let tap = UITapGestureRecognizer(target: self, action: #selector(tapped))
            tap.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.indirect.rawValue)]
            tap.allowedPressTypes = []   // clicks stay with SwiftUI (they open the guide)
            tap.cancelsTouchesInView = false
            window.addGestureRecognizer(tap)
            recognizer = tap
        }

        func detach() {
            if let recognizer { recognizer.view?.removeGestureRecognizer(recognizer) }
            recognizer = nil
        }

        @objc private func tapped() {
            if isEnabled { action() }
        }
    }

    /// Attaches the recognizer once the view is in a window, and removes it when it leaves.
    final class WindowWatcher: UIView {
        weak var coordinator: Coordinator?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if let window { coordinator?.attach(to: window) } else { coordinator?.detach() }
        }
    }
}
