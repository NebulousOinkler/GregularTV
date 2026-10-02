import GregularScreens
import JavaScriptKit

/// A page: something drawn in the app's place, and taken down when it goes.
@MainActor protocol Page: AnyObject {
    var element: El { get }
    /// It's on the page now: put focus where it starts.
    func appeared()
    /// It's going: stop its timers and redraws, and let go of the keyboard.
    func close()
}

extension Page {
    func appeared() {}
}

/// The pieces pages are built from, so they look and behave the same
/// (`app.css` styles each by its class).
@MainActor enum Parts {
    /// The name and its colour bars, small, for the app bar.
    static func brand() -> El {
        El("div", "brand", [El("span", "wordmark", text: "Gregular TV"), colourBars()])
            .attribute("role", "img").attribute("aria-label", "Gregular TV")
    }

    /// The name, colour bars and tagline, large, for the start.
    static func hero() -> El {
        El("div", "hero", [
            El("h1", "wordmark", text: "Gregular TV"),
            colourBars(),
            El("p", "tagline", text: "We now return to your Gregular programming."),
        ])
    }

    /// The bar along the top of a page: the brand, and anything on the right.
    static func appBar(_ trailing: [El] = []) -> El {
        El("header", "app-bar", [brand(), El("div", "buttons", trailing)])
    }

    /// Links to the help and privacy pages, at the foot of a page.
    static func footer() -> El {
        let help = El("a", text: "Help").attribute("href", "help.html")
        let privacy = El("a", text: "Privacy").attribute("href", "privacy.html")
        return El("footer", "page-footer", [help, privacy])
    }

    /// The slim pill of colour bars.
    static func colourBars(_ classes: String = "bars") -> El {
        El("div", classes, (0..<7).map { El("span", "bar bar-\($0)") }).attribute("aria-hidden", "true")
    }

    static func spinner(_ label: String = "Loading") -> El {
        El("div", "spinner").attribute("role", "progressbar").attribute("aria-label", label)
    }

    /// A note set apart: `kind` "warn" or "danger", or "" for a plain one.
    static func callout(_ text: String, kind: String = "", icon: Icon = .info) -> El {
        El("div", "callout \(kind)", [icon.element, El("p", text: text)])
    }

    /// A group of rows with a heading and notes underneath (nil notes are
    /// left out). `role` "radiogroup" for a choice of one.
    static func section(_ title: String?, footer: [String?] = [], role: String? = nil, rows: [El]) -> El {
        let section = El("section", "rows")
        let box = El("div", "rows-box", rows)
        if let title {
            let heading = El("h3", "group-title", text: title)
            section.append(heading)
            box.attribute("aria-label", title)
        }
        if let role { box.attribute("role", role) }
        if !rows.isEmpty { section.append(box) }
        for note in footer.compactMap({ $0 }) { section.append(El("p", "note", text: note)) }
        return section
    }

    /// A row: a title with an optional detail line, and a value on the right.
    static func row(_ title: String, detail: String? = nil, value: String? = nil, destructive: Bool = false,
                    action: (@MainActor () -> Void)?) -> El {
        let row = El(action == nil ? "div" : "button", "row" + (destructive ? " destructive" : ""), [text(title, detail)])
        if let value { row.append(El("span", "row-value", text: value)) }
        if let action {
            row.attribute("type", "button")
            row.append(Icon.chevronRight.element)
            row.on("click") { _ in action() }
        }
        return row
    }

    /// One of a choice (in a `section` with role "radiogroup"): checked or not.
    static func choice(_ title: String, detail: String? = nil, checked: Bool, action: @escaping @MainActor () -> Void) -> El {
        let row = El("button", "row" + (checked ? " checked" : ""), [text(title, detail)])
        row.attribute("type", "button").attribute("role", "radio").attribute("aria-checked", checked ? "true" : "false")
        if checked { row.append(El("span", "check", [Icon.check.element])) }
        row.on("click") { _ in action() }
        return row
    }

    /// A switch: on or off.
    static func toggle(_ title: String, detail: String? = nil, on: Bool, action: @escaping @MainActor () -> Void) -> El {
        let row = El("button", "row", [text(title, detail), El("span", "switch").attribute("aria-hidden", "true")])
        row.attribute("type", "button").attribute("role", "switch").attribute("aria-checked", on ? "true" : "false")
        row.on("click") { _ in action() }
        return row
    }

    /// A label and its value, not a button, lined up with the rows.
    static func info(_ title: String, _ value: String) -> El {
        El("div", "row info", [text(title, nil), El("span", "row-value", text: value)])
    }

    private static func text(_ title: String, _ detail: String?) -> El {
        let text = El("span", "row-text", [El("span", "row-title", text: title)])
        if let detail { text.append(El("span", "row-detail", text: detail)) }
        return text
    }

    /// A panel over live TV: a full-screen sheet on a phone, a side sheet on
    /// a larger screen. Its bar has the title, `actions` and Close.
    static func sheet(_ classes: String, title: String, actions: [El] = [], close: @escaping @MainActor () -> Void) -> (sheet: El, body: El) {
        let heading = El("h2", text: title)
        let id = "sheet-" + classes
        heading.attribute("id", id)
        let body = El("div", "sheet-body")
        let sheet = El("section", "sheet " + classes, [
            El("div", "sheet-bar", [heading] + actions + [El.button("Close", icon: .close, "icon-button", labelHidden: true, action: close)]),
            body,
        ])
        sheet.attribute("role", "dialog").attribute("aria-labelledby", id)
        return (sheet, body)
    }

    /// Asks `confirmation`'s question in a dialog, and runs `action` if the
    /// viewer agrees. Escape or Cancel leaves everything as it was.
    static func confirm(_ confirmation: Confirmation, then action: @escaping @MainActor () -> Void) {
        let dialog = El("dialog", "confirm")
        let previous = DOM.focused
        let cancel = El.button("Cancel") { _ = dialog.object.close!() }
        let go = El.button(confirmation.action, "destructive") {
            _ = dialog.object.close!()
            action()
        }
        let question = El("h2", text: confirmation.question).attribute("id", "confirm-question")
        let detail = El("p", text: confirmation.detail).attribute("id", "confirm-detail")
        dialog.attribute("aria-labelledby", "confirm-question").attribute("aria-describedby", "confirm-detail")
        dialog.append(question, detail, El("div", "buttons", [cancel, go]))
        dialog.on("close") { _ in
            dialog.remove()
            _ = previous?.focus!()
        }
        El(DOM.document.body.object!).append(dialog)
        _ = dialog.object.showModal!()
        cancel.focus()
    }
}
