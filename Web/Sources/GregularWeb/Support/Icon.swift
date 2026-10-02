import JavaScriptKit

/// The app's icons: simple line drawings on a 24-point grid, drawn as inline
/// SVG in the current text colour, so they follow the theme and scale with
/// the text. Every one is decorative (`aria-hidden`): the button or label
/// it sits in carries the words.
@MainActor enum Icon: String {
    case play, pause, previous, next, guide, list, info, settings, servers
    case fullScreen, exitFullScreen, close, back, plus, server, tv, warning, check
    case signOut, chevronRight, sound, lock

    /// The drawing: SVG path data, stroked.
    private var paths: [String] {
        switch self {
        case .play: ["M7 4.5v15l12-7.5z"]
        case .pause: ["M8 5v14", "M16 5v14"]
        case .previous: ["M15 18l-6-6 6-6"]
        case .next: ["M9 18l6-6-6-6"]
        case .guide: ["M3 5h18v14H3z", "M3 10h18", "M9 10v9", "M15 10v9"]
        case .list: ["M8 6h13", "M8 12h13", "M8 18h13", "M3.5 6h.01", "M3.5 12h.01", "M3.5 18h.01"]
        case .info: ["M12 22a10 10 0 1 0 0-20 10 10 0 0 0 0 20z", "M12 16v-4", "M12 8h.01"]
        case .settings: ["M12 15a3 3 0 1 0 0-6 3 3 0 0 0 0 6z",
                         "M19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.8-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 0 1-4 0v-.1a1.7 1.7 0 0 0-1.1-1.5 1.7 1.7 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.8 1.7 1.7 0 0 0-1.5-1H3a2 2 0 0 1 0-4h.1a1.7 1.7 0 0 0 1.5-1.1 1.7 1.7 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.8.3H9a1.7 1.7 0 0 0 1-1.5V3a2 2 0 0 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.8V9a1.7 1.7 0 0 0 1.5 1H21a2 2 0 0 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1z"]
        case .servers: ["M4 4h16v6H4z", "M4 14h16v6H4z", "M8 7h.01", "M8 17h.01"]
        case .fullScreen: ["M8 3H5a2 2 0 0 0-2 2v3", "M21 8V5a2 2 0 0 0-2-2h-3", "M3 16v3a2 2 0 0 0 2 2h3", "M16 21h3a2 2 0 0 0 2-2v-3"]
        case .exitFullScreen: ["M8 3v3a2 2 0 0 1-2 2H3", "M21 8h-3a2 2 0 0 1-2-2V3", "M3 16h3a2 2 0 0 1 2 2v3", "M16 21v-3a2 2 0 0 1 2-2h3"]
        case .close: ["M18 6L6 18", "M6 6l12 12"]
        case .back: ["M19 12H5", "M12 19l-7-7 7-7"]
        case .plus: ["M12 5v14", "M5 12h14"]
        case .server: ["M3 6a3 3 0 0 1 3-3h12a3 3 0 0 1 3 3v2a3 3 0 0 1-3 3H6a3 3 0 0 1-3-3z",
                       "M3 16a3 3 0 0 1 3-3h12a3 3 0 0 1 3 3v2a3 3 0 0 1-3 3H6a3 3 0 0 1-3-3z", "M7 7h.01", "M7 17h.01"]
        case .tv: ["M3 7h18v12H3z", "M8 3l4 4 4-4"]
        case .warning: ["M10.3 3.9L1.8 18a2 2 0 0 0 1.7 3h17a2 2 0 0 0 1.7-3L13.7 3.9a2 2 0 0 0-3.4 0z", "M12 9v4", "M12 17h.01"]
        case .check: ["M20 6L9 17l-5-5"]
        case .signOut: ["M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4", "M16 17l5-5-5-5", "M21 12H9"]
        case .chevronRight: ["M9 18l6-6-6-6"]
        case .sound: ["M11 5L6 9H2v6h4l5 4z", "M15.5 8.5a5 5 0 0 1 0 7", "M19 5a10 10 0 0 1 0 14"]
        case .lock: ["M5 11h14v10H5z", "M8 11V7a4 4 0 0 1 8 0v4"]
        }
    }

    /// The icon, as an element to put in a button or label.
    var element: El {
        let namespace = "http://www.w3.org/2000/svg"
        let svg = El(DOM.document.createElementNS!(namespace, "svg").object!)
        svg.attribute("viewBox", "0 0 24 24").attribute("aria-hidden", "true").attribute("focusable", "false")
            .attribute("class", "icon icon-\(rawValue)")
        for data in paths {
            let path = El(DOM.document.createElementNS!(namespace, "path").object!)
            path.attribute("d", data)
            svg.append(path)
        }
        return svg
    }
}

extension El {
    /// A button with an icon and its words: shown, or (`labelHidden`) read
    /// out to screen readers and shown as a tooltip.
    static func button(_ title: String, icon: Icon, _ classes: String = "", labelHidden: Bool = false,
                       action: @escaping @MainActor () -> Void) -> El {
        let button = El("button", classes)
        button.attribute("type", "button")
        button.append(icon.element)
        if labelHidden {
            button.attribute("aria-label", title).attribute("title", title)
        } else {
            button.append(El("span", "label", text: title))
        }
        button.on("click") { _ in action() }
        return button
    }
}
