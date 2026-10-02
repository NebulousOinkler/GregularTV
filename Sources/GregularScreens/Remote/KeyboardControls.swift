/// A computer keyboard, as the web version's remote: each key presses one
/// of the remote's buttons, so `RemoteControls`' tables decide what it does
/// on every screen, as on Apple TV, and the hints come from the same tables.
///
/// Keys are named as the browser's `KeyboardEvent.key` names them (letters
/// in lower case). Fixed, as on Apple TV: digits type a channel number, and
/// in the channel list, guide and Settings the arrows move the highlight; one
/// with nowhere to go there counts as the remote's click or slide that way.
public enum KeyboardControls {
    public static let buttons: [String: RemoteButton] = [
        "ArrowUp": .clickUp,
        "ArrowDown": .clickDown,
        "ArrowLeft": .clickLeft,
        "ArrowRight": .clickRight,
        "Enter": .click,
        "l": .swipeLeft,
        "i": .touchTap,
        "s": .clickAndHold,
        " ": .playPause,
        "k": .playPause,
        "Escape": .menu,
        "Backspace": .menu,
    ]

    /// The key for `button` as hints name it, or nil if no key presses it.
    public static func name(of button: RemoteButton) -> String? {
        switch button {
        case .clickUp: "↑"
        case .clickDown: "↓"
        case .clickLeft: "←"
        case .clickRight: "→"
        case .click: "Enter"
        case .swipeLeft: "L"
        case .touchTap: "I"
        case .clickAndHold: "S"
        case .playPause: "Space"
        case .menu: "Esc"
        case .swipeUp, .swipeDown, .swipeRight: nil
        }
    }

    /// Hints in the keyboard's names: "← →: channels · L: channel list · …".
    public static let names = RemoteControls.ButtonNames(name: name(of:)) { down, up in
        switch (down, up) {
        case (.clickDown, .clickUp): "↓ ↑"
        case (.clickLeft, .clickRight): "← →"
        default: nil
        }
    }

    /// The button a key presses, if any.
    public static func button(forKey key: String) -> RemoteButton? {
        buttons[key] ?? buttons[key.lowercased()]
    }
}
