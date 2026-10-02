import Foundation
import GregularScreens
import JavaScriptKit

/// Your channels and set times, edited in the same page the Apple TV serves
/// to phones (`editor.html`, made from GregularScreens' `Editing/Page`
/// files by scripts/build-web.sh). It opens in a frame over Settings and
/// asks this app directly (`window.gregularEditor`, answered by
/// `EditingAPI`): no network and no code, since it's the same app.
@MainActor final class ChannelEditor {
    let element = El("div", "channel-editor")
    private let frame = El("iframe")
    private let onClose: () -> Void

    init(app: AppModel, onClose: @escaping () -> Void) {
        self.onClose = onClose
        let api = EditingAPI(app: app)
        let host = JSObject()
        host["request"] = .object(JSClosure { arguments in
            let method = arguments[0].string ?? "GET"
            let path = arguments[1].string ?? ""
            let body = Data((arguments[2].string ?? "").utf8)
            return Self.promise {
                let response = await api.answer(method, path, body)
                let reply = JSObject()
                reply["status"] = .number(Double(response.status))
                reply["body"] = .string(String(decoding: response.body, as: UTF8.self))
                return .object(reply)
            }
        })
        JSObject.global.gregularEditor = .object(host)

        frame.attribute("src", "editor.html").attribute("title", "Your channels and set times")
        let close = El.button("Close", icon: .close, "icon-button", labelHidden: true) { [weak self] in self?.askToClose() }
        element.attribute("role", "dialog").attribute("aria-label", "Your channels and set times")
        element.append(El("div", "sheet-bar", [El("h2", text: "Your channels and set times"), close]), frame)
        Keys.take(KeyTrap.shared)
        Task { close.focus() }
    }

    /// Closes, first asking if there are changes not saved.
    private func askToClose() {
        let dirty = JSObject.global.gregularEditor.isDirty.function.map { $0().boolean == true } ?? false
        guard dirty else { return close() }
        Parts.confirm(.discardEdits) { [weak self] in self?.close() }
    }

    func close() {
        element.remove()
        JSObject.global.gregularEditor = .undefined
        Keys.release(KeyTrap.shared)
        onClose()
    }

    /// A promise for `work`'s result, for the page in the frame.
    private static func promise(_ work: @escaping @MainActor () async -> JSValue) -> JSValue {
        JSPromise { resolve in
            let resolve = Resolve(resolve: resolve)
            Task { @MainActor in resolve.resolve(.success(await work())) }
        }.jsValue
    }

    /// The promise's resolve function, carried into the task (JavaScript
    /// runs on one thread, so it's safe).
    private struct Resolve: @unchecked Sendable {
        let resolve: (JSPromise.Result) -> Void
    }
}

/// Takes the keyboard while the editor is open, so keys there never reach
/// live TV or Settings underneath.
@MainActor final class KeyTrap: KeyTarget {
    static let shared = KeyTrap()

    func press(_ button: RemoteButton) -> Bool { false }
}
