import Foundation
import GregularScreens

/// What the channel list, guide and Settings do with a key: the arrows move
/// the highlight, and one with nowhere to go counts as the remote's click or
/// slide that way (as tvOS reports both as the same arrow there); the rest
/// do what `table` says. Enter is left to the highlighted button.
@MainActor enum Overlay {
    static func press(_ button: RemoteButton, table: [RemoteButton: RemoteAction], within container: El,
                      onRemote: (RemoteAction) -> Void) -> Bool {
        if let direction = button.direction {
            if Focus.move(direction, within: container) { return true }
            let action = RemoteButton.allCases.lazy.filter { $0.direction == direction }.compactMap { table[$0] }.first
            guard let action else { return false }
            onRemote(action)
            return true
        }
        guard button != .click, let action = table[button] else { return false }
        onRemote(action)
        return true
    }
}

/// Calls `action` after a while with no key, click or mouse movement.
@MainActor final class IdleTimer {
    private let seconds: TimeInterval
    private let action: () -> Void
    private var task: Task<Void, Never>?

    init(after seconds: TimeInterval, action: @escaping () -> Void) {
        self.seconds = seconds
        self.action = action
        reset()
    }

    /// Any activity in `element` starts the wait again.
    func watch(_ element: El) {
        for event in ["pointermove", "pointerdown", "wheel", "focusin"] {
            element.on(event) { [weak self] _ in self?.reset() }
        }
    }

    func reset() {
        task?.cancel()
        let seconds = seconds
        task = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.action()
        }
    }

    func stop() {
        task?.cancel()
    }
}
