import GregularScreens
import JavaScriptKit

/// Something on screen that takes the keyboard: the page on top.
@MainActor protocol KeyTarget: AnyObject {
    /// A key pressed one of the remote's buttons (`KeyboardControls`).
    /// True if it did something.
    func press(_ button: RemoteButton) -> Bool
    /// A digit typed (a channel number). True if it did something.
    func type(digit: Character) -> Bool
}

extension KeyTarget {
    func type(digit: Character) -> Bool { false }
}

/// The keyboard, sent to whichever page is on top (`target`). Keys typed
/// into a text field stay there, but Escape and arrows that leave it.
@MainActor enum Keys {
    /// The pages taking the keyboard, the top one last.
    private static var targets: [KeyTarget] = []

    /// `target` takes the keyboard until `release(_:)`.
    static func take(_ target: KeyTarget) {
        targets.removeAll { $0 === target }
        targets.append(target)
    }

    static func release(_ target: KeyTarget) {
        targets.removeAll { $0 === target }
    }

    static func start() {
        El(DOM.document).on("keydown") { event in
            guard event.defaultPrevented.boolean != true, event.isComposing.boolean != true,
                  event.ctrlKey.boolean != true, event.metaKey.boolean != true, event.altKey.boolean != true,
                  let key = event.key.string else { return }
            if handle(key, typing: isTyping(event.target.object)) { _ = event.preventDefault!() }
        }
    }

    private static func handle(_ key: String, typing: Bool) -> Bool {
        // A dialog open over the page (a confirmation) has the keyboard to itself.
        guard let target = targets.last, DOM.document.querySelector!("dialog[open]").isNull else { return false }
        // In a text field, only Escape (and Enter, which the field's form handles) leave it.
        if typing && key != "Escape" { return false }
        if key.count == 1, let digit = key.first, digit.isASCII, digit.isNumber {
            return target.type(digit: digit)
        }
        guard let button = KeyboardControls.button(forKey: key) else { return false }
        return target.press(button)
    }

    private static func isTyping(_ element: JSObject?) -> Bool {
        guard let element, let tag = element.tagName.string?.lowercased() else { return false }
        if tag == "textarea" || element.isContentEditable.boolean == true { return true }
        guard tag == "input" else { return false }
        let type = element.type.string ?? "text"
        return !["button", "checkbox", "radio", "submit", "reset"].contains(type)
    }
}

/// Moves focus with the arrow keys between the buttons in a part of the
/// page: to the nearest one in that direction, as a TV's remote does.
@MainActor enum Focus {
    /// Moves focus within `container`. False if there's nothing that way.
    static func move(_ direction: RemoteDirection, within container: El) -> Bool {
        let candidates = focusable(in: container)
        guard let current = DOM.focused, let from = candidates.first(where: { $0.object == current }) else {
            // Nothing focused yet here: start at the first.
            candidates.first?.focus()
            return !candidates.isEmpty
        }
        let start = rect(of: from)
        let best = candidates.filter { $0.object != current }
            .compactMap { candidate -> (El, Double)? in
                let to = rect(of: candidate)
                let (along, across) = switch direction {
                case .up: (start.top - to.bottom + 1, overlap(start.left, start.right, to.left, to.right))
                case .down: (to.top - start.bottom + 1, overlap(start.left, start.right, to.left, to.right))
                case .left: (start.left - to.right + 1, overlap(start.top, start.bottom, to.top, to.bottom))
                case .right: (to.left - start.right + 1, overlap(start.top, start.bottom, to.top, to.bottom))
                }
                guard along > 0 else { return nil }
                // Nearest that way, favouring ones lined up with this one.
                return (candidate, along + (across > 0 ? 0 : 1000 + abs(centre(start, direction) - centre(to, direction))))
            }
            .min { $0.1 < $1.1 }?.0
        guard let best else { return false }
        best.focus()
        _ = best.object.scrollIntoView!(JSObject.options(["block": "nearest", "inline": "nearest"]))
        return true
    }

    /// The things that can take focus in `container`, as shown.
    static func focusable(in container: El) -> [El] {
        let list = container.object.querySelectorAll!("button:not([disabled]), input, [data-focus]").object!
        let count = Int(list.length.number ?? 0)
        return (0..<count).compactMap { list[$0].object }.map(El.init)
            .filter { $0.object.offsetParent.isNull == false || $0.object.getClientRects!().length.number ?? 0 > 0 }
    }

    private struct Rect { let left, top, right, bottom: Double }

    private static func rect(of element: El) -> Rect {
        let box = element.object.getBoundingClientRect!().object!
        return Rect(left: box.left.number ?? 0, top: box.top.number ?? 0, right: box.right.number ?? 0, bottom: box.bottom.number ?? 0)
    }

    private static func overlap(_ a1: Double, _ a2: Double, _ b1: Double, _ b2: Double) -> Double {
        min(a2, b2) - max(a1, b1)
    }

    private static func centre(_ rect: Rect, _ direction: RemoteDirection) -> Double {
        switch direction {
        case .up, .down: (rect.left + rect.right) / 2
        case .left, .right: (rect.top + rect.bottom) / 2
        }
    }
}
