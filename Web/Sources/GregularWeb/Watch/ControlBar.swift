import GregularBrowser
import JavaScriptKit

/// Full screen: the whole page, so the controls, guide and Settings come too.
@MainActor enum FullScreen {
    /// Called when full screen starts or ends, by any route (Escape included).
    static var onChange: (() -> Void)? {
        didSet { listen() }
    }

    static var isOn: Bool { !DOM.document.fullscreenElement.isNull && !DOM.document.fullscreenElement.isUndefined }

    /// Whether this browser can (iPhone Safari can't, for a page).
    static var isAvailable: Bool { DOM.document.fullscreenEnabled.boolean == true }

    static func toggle() {
        if isOn {
            _ = DOM.document.exitFullscreen?()
        } else {
            _ = DOM.document.documentElement.object?.requestFullscreen?()
        }
    }

    private static var listening = false

    private static func listen() {
        guard !listening else { return }
        listening = true
        El(DOM.document).on("fullscreenchange") { _ in onChange?() }
    }
}

/// Keeps the screen on while live TV is on screen (where the browser
/// allows it). The browser lets go when the tab is hidden, so it's asked
/// again when the tab comes back.
@MainActor final class WakeLock {
    private var lock: JSObject?
    private var wanted = false

    init() {
        El(DOM.document).on("visibilitychange") { [weak self] _ in
            guard let self, self.wanted, DOM.document.visibilityState.string == "visible" else { return }
            self.request()
        }
    }

    func request() {
        wanted = true
        guard let wakeLock = JSObject.global.navigator.wakeLock.object else { return }
        Task {
            lock = try? await wakeLock.request!("screen").promised().object
        }
    }

    func release() {
        wanted = false
        _ = lock?.release?()
        lock = nil
    }
}
