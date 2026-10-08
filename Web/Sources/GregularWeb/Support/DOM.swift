import JavaScriptKit

/// One element on the page, and the few things the pages do to elements.
///
/// Text from anywhere (names from the server above all) is only ever put on
/// the page as text (`textContent`), never as HTML: there's no way here to
/// set HTML at all. GregularScreens hands every string over as plain text.
@MainActor struct El {
    let object: JSObject

    init(_ object: JSObject) {
        self.object = object
    }

    /// A new `<tag>` with these classes and children.
    init(_ tag: String, _ classes: String = "", _ children: [El] = []) {
        object = DOM.document.createElement!(tag).object!
        if !classes.isEmpty { object.className = .string(classes) }
        for child in children { _ = object.append!(child.object) }
    }

    /// A new `<tag>` with these children and no classes.
    init(_ tag: String, _ children: [El]) {
        self.init(tag, "", children)
    }

    /// A new `<tag>` holding `text`.
    init(_ tag: String, _ classes: String = "", text: String) {
        self.init(tag, classes)
        self.text = text
    }

    /// The element with this ID, which the page must have.
    static func byID(_ id: String) -> El {
        El(DOM.document.getElementById!(id).object!)
    }

    var text: String {
        get { object.textContent.string ?? "" }
        nonmutating set {
            // Only when it changes: setting it replaces the node, which resets selection and screen readers.
            if text != newValue { object.textContent = .string(newValue) }
        }
    }

    /// Sets an attribute, or removes it for nil.
    @discardableResult
    func attribute(_ name: String, _ value: String?) -> El {
        if let value { _ = object.setAttribute!(name, value) } else { _ = object.removeAttribute!(name) }
        return self
    }

    /// Turns a class on or off.
    func classed(_ name: String, _ on: Bool) {
        _ = object.classList.toggle(name, on)
    }

    /// Out of reach while something is open over it: no focus, no clicks,
    /// and hidden from screen readers.
    var inert: Bool {
        get { object.inert.boolean ?? false }
        nonmutating set { object.inert = .boolean(newValue) }
    }

    var hidden: Bool {
        get { object.hidden.boolean ?? false }
        nonmutating set { object.hidden = .boolean(newValue) }
    }

    /// A CSS property, such as `style("opacity", "0")`.
    func style(_ property: String, _ value: String) {
        _ = object.style.setProperty(property, value)
    }

    /// Sets style properties ("--i: 3; left: 10%"), through the style object:
    /// the page's Content Security Policy refuses `style` attributes.
    @discardableResult
    func styled(_ declarations: String) -> El {
        func trimmed(_ text: Substring) -> String {
            String(text.drop { $0 == " " }.reversed().drop { $0 == " " }.reversed())
        }
        for declaration in declarations.split(separator: ";") {
            let parts = declaration.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }
            style(trimmed(parts[0]), trimmed(parts[1]))
        }
        return self
    }

    func append(_ children: El...) {
        for child in children { _ = object.append!(child.object) }
    }

    /// Replaces everything inside it.
    func replaceChildren(_ children: [El]) {
        let replace = object.replaceChildren.function!
        _ = replace(this: object, arguments: children.map { $0.object.jsValue })
    }

    func remove() {
        _ = object.remove!()
    }

    /// Stops a `<video>` and lets go of what it was playing.
    func emptyVideo() {
        _ = object.pause!()
        _ = object.removeAttribute!("src")
        _ = object.load!()
    }

    func focus() {
        _ = object.focus!()
    }

    /// Calls `handler` with the event each time it happens.
    @discardableResult
    func on(_ event: String, _ handler: @escaping @MainActor (JSObject) -> Void) -> El {
        let closure = JSClosure { arguments in
            MainActor.assumeIsolated { handler(arguments[0].object!) }
            return .undefined
        }
        _ = object.addEventListener!(event, closure)
        return self
    }

    /// A button that runs `action` when clicked (or pressed with Enter or Space).
    static func button(_ title: String, _ classes: String = "", action: @escaping @MainActor () -> Void) -> El {
        let button = El("button", classes, text: title)
        button.attribute("type", "button")
        button.on("click") { _ in action() }
        return button
    }
}

/// The page itself.
@MainActor enum DOM {
    static var document: JSObject { JSObject.global.document.object! }
    static var window: JSObject { JSObject.global.window.object! }

    /// The element with focus, if any.
    static var focused: JSObject? {
        document.activeElement.object
    }
}

extension JSObject {
    /// An options object for a browser call, such as `["block": "center"]`.
    @MainActor static func options(_ values: [String: String]) -> JSObject {
        let object = JSObject()
        for (key, value) in values { object[key] = .string(value) }
        return object
    }
}
