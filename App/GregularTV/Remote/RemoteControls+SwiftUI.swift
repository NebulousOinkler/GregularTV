import GregularScreens
import SwiftUI

// MARK: - Attaching a table to a view

extension View {
    /// Sends the table's buttons to `perform` while this view (or something
    /// inside it) has focus. Buttons not in the table keep their usual tvOS behaviour.
    /// Edge clicks, swipes and `.touchTap` while watching are handled
    /// separately, by `RemoteGestures`, which can tell them apart.
    /// - Parameter takesClicks: whether `.click` and `.clickAndHold` apply. Only
    ///   for a view with no buttons inside, since it would take their clicks.
    /// - Parameter takesArrows: whether edge clicks and swipes are handled here,
    ///   as SwiftUI's arrows (which can't tell a click from a swipe).
    func remoteControls(_ map: [RemoteButton: RemoteAction], takesClicks: Bool = false, takesArrows: Bool = true,
                        perform: @escaping (RemoteAction) -> Void) -> some View {
        modifier(RemoteControlsModifier(map: map, takesClicks: takesClicks, takesArrows: takesArrows, perform: perform))
    }
}

private struct RemoteControlsModifier: ViewModifier {
    let map: [RemoteButton: RemoteAction]
    let takesClicks: Bool
    let takesArrows: Bool
    let perform: (RemoteAction) -> Void

    func body(content: Content) -> some View {
        let onMove: ((MoveCommandDirection) -> Void)? = hasArrows ? { move($0) } : nil
        let onPlayPause: (() -> Void)? = handler(for: .playPause)
        // Leaving this nil keeps Menu's usual job (going back, or Home).
        let onMenu: (() -> Void)? = handler(for: .menu)
        let clicks = ClickGestures(click: takesClicks ? handler(for: .click) : nil,
                                   hold: takesClicks ? handler(for: .clickAndHold) : nil)
        return content
            .onMoveCommand(perform: onMove)
            .onPlayPauseCommand(perform: onPlayPause)
            .onExitCommand(perform: onMenu)
            .modifier(clicks)
    }

    private var hasArrows: Bool {
        takesArrows && map.keys.contains { $0.direction != nil }
    }

    /// An arrow here is a click or a swipe: whichever is mapped (the click if both).
    private func move(_ command: MoveCommandDirection) {
        let direction: RemoteDirection? = switch command {
        case .up: .up
        case .down: .down
        case .left: .left
        case .right: .right
        @unknown default: nil
        }
        guard let direction else { return }
        let action = RemoteButton.allCases.lazy.filter { $0.direction == direction }.compactMap { map[$0] }.first
        if let action { perform(action) }
    }

    private func handler(for button: RemoteButton) -> (() -> Void)? {
        guard let action = map[button] else { return nil }
        let perform = perform
        return { perform(action) }
    }
}

/// Click and click-and-hold, only when mapped: a tap gesture on a container
/// would otherwise take clicks meant for the buttons inside it.
private struct ClickGestures: ViewModifier {
    let click: (() -> Void)?
    let hold: (() -> Void)?

    func body(content: Content) -> some View {
        switch (click, hold) {
        case let (click?, hold?):
            // The hold is declared first, so a quick click isn't taken as the start of one.
            content.onLongPressGesture(minimumDuration: 0.6, perform: hold).onTapGesture(perform: click)
        case let (click?, nil):
            content.onTapGesture(perform: click)
        case let (nil, hold?):
            content.onLongPressGesture(minimumDuration: 0.6, perform: hold)
        case (nil, nil):
            content
        }
    }
}
