import Foundation
import GregularBrowser
import GregularCore
import GregularScreens
import JavaScriptKit

/// Gregular TV in a browser: the same `AppModel` as on Apple TV, drawn as
/// web pages, playing through `<video>`, with the browser's network path and
/// storage. What happens is all decided in GregularScreens; this only draws
/// it and connects the keyboard and mouse.
@MainActor enum WebApp {
    /// How this app appears in the server's device list: the kind of
    /// device, never anything about this particular browser.
    static let deviceName = "Web Browser"

    static func start() async {
        Keys.start()
        // Browsers allow sound only after the viewer has clicked or pressed a key.
        for event in ["pointerdown", "keydown"] {
            El(DOM.document).on(event) { _ in SoundUnlock.unlock() }
        }
        let app: AppModel
        #if DEBUG
        if let server = demoServer {
            app = AppModel(deviceName: deviceName, formats: formats, transport: FetchTransport(),
                           store: DemoCredentials(server: server), preferences: AppPreferences(storage: preferences),
                           makeDecks: VideoDeck.pair, specialModes: SpecialModePages.all.registry)
            return await run(app)
        }
        #endif
        let store = await BrowserCredentialStore.load()
        signIns = store
        app = AppModel(deviceName: deviceName, formats: formats, transport: FetchTransport(), store: store,
                       preferences: AppPreferences(storage: preferences), makeDecks: VideoDeck.pair,
                       specialModes: SpecialModePages.all.registry)
        await run(app)
    }

    private static func run(_ app: AppModel) async {
        self.app = app
        root = Root(app: app, in: El.byID("app"))
        await app.launch()
    }

    /// Kept for the life of the page.
    private static var root: Root?
    private static var app: AppModel?
    /// The sign-ins saved in this browser (none in demo mode).
    private(set) static var signIns: BrowserCredentialStore?
    private static let preferences = BrowserPreferences()

    /// Signs out of every server (so their sign-ins stop working there too),
    /// forgets everything kept in this browser, and starts again.
    static func forgetEverything() async {
        if let app {
            for server in app.servers { await app.signOut(of: server) }
        }
        try? signIns?.deleteAll()
        await signIns?.settle()
        preferences.removeAll()
        _ = DOM.window.location.reload()
    }

    #if DEBUG
    /// Demo mode, in Debug builds: `?demoServer=http://127.0.0.1:8765`
    /// (scripts/demo-server.py) signs in there, held in memory only.
    private static var demoServer: URL? {
        let query = JSObject.global.URLSearchParams.function!.new(DOM.window.location.search)
        return query.get!("demoServer").string.flatMap(URL.init(string:))
    }
    #endif

    private static var formats: PlayableFormats { .browser(playsHEVC: playsHEVC) }

    /// Whether this browser plays HEVC (H.265) video, so the server can send it as it is.
    private static var playsHEVC: Bool {
        guard let mediaSource = JSObject.global.MediaSource.function else { return false }
        return mediaSource.isTypeSupported!("video/mp4; codecs=\"hvc1.1.6.L120.90\"").boolean == true
    }
}

/// Everything on screen: live TV underneath (when a channel is playing, on
/// screen or behind the main page), and the page for the app's phase above.
@MainActor final class Root {
    private let app: AppModel
    private let live = El("div", "live")
    private let pageLayer = El("div", "page-layer")
    private var watch: WatchScreen?
    private var page: (any Page)?
    private var pageKey = ""
    private var redraws: [Redraw] = []

    init(app: AppModel, in container: El) {
        self.app = app
        container.replaceChildren([live, pageLayer])
        redraws = [
            Redraw { [weak self] in self?.drawLiveTV() },
            Redraw { [weak self] in self?.drawPage() },
        ]
    }

    /// Live TV keeps its place whether it's on screen or behind the main
    /// page, so going up to the page and back never rebuilds it (or re-tunes).
    private func drawLiveTV() {
        let surfer = app.liveTV
        _ = DOM.document.body.object!.classList.toggle("watching", surfer != nil)
        if watch?.surfer !== surfer {
            watch?.close()
            watch = surfer.map { WatchScreen(surfer: $0, app: app) }
            live.replaceChildren(watch.map { [$0.element] } ?? [])
        }
        watch?.isCovered = app.isOverLiveTV
    }

    /// A new page only when the phase changes; each page redraws its own details.
    private func drawPage() {
        let phase = app.phase
        let key = switch phase {
        case .launching: "launching"
        case .signedOut: "signedOut"
        case .mainPage: "mainPage"
        case .loading: "loading"
        case .watching: "watching"
        case .special(let session): "special:\(ObjectIdentifier(session))"
        case .failed(let message): "failed:" + message
        }
        guard key != pageKey else { return }
        pageKey = key
        page?.close()
        page = switch phase {
        case .launching: WaitPage(message: nil)
        case .signedOut: LoginPage(app: app)
        case .mainPage: MainPage(app: app)
        case .loading: WaitPage(message: "Loading your library…")
        case .watching: nil   // drawn underneath
        case .special(let session): SpecialModePages.all.screen(for: session)
        case .failed(let message): FailedPage(app: app, message: message)
        }
        pageLayer.replaceChildren(page.map { [$0.element] } ?? [])
        page?.appeared()
    }
}

/// The name, tagline and a spinner, while the app starts or loads the library.
@MainActor final class WaitPage: Page {
    let element: El

    init(message: String?) {
        let content = El("div", "content centred wait", [Parts.hero(), Parts.spinner(message ?? "Starting")])
        if let message { content.append(El("p", "note", text: message).attribute("role", "status")) }
        element = El("main", "page", [content])
    }

    func close() {}
}

/// The library couldn't be loaded. A TV (or a browser left open) is often
/// left on, so it tries again by itself every 30 seconds.
@MainActor final class FailedPage: Page, KeyTarget {
    let element: El
    private let tryAgain: El
    private var retrying: Task<Void, Never>?

    init(app: AppModel, message: String) {
        tryAgain = El.button("Try Again", "primary") { Task { await app.retry() } }
        let icon = Icon.warning.element
        icon.attribute("class", "icon icon-large")
        element = El("main", "page", [
            Parts.appBar(),
            El("div", "content centred failure", [
                icon,
                El("h1", "page-title", text: "Can't load your channels"),
                El("p", "page-lede", text: message).attribute("role", "alert"),
                El("p", "note", text: "Trying again automatically every 30 seconds."),
                El("div", "buttons", [El.button("All Servers", "quiet") { app.showMainPage() }, tryAgain]),
            ]),
        ])
        retrying = Task {
            try? await Task.sleep(for: .seconds(30))
            guard !Task.isCancelled else { return }
            await app.retry()
        }
        Keys.take(self)
    }

    func appeared() {
        tryAgain.focus()
    }

    func press(_ button: RemoteButton) -> Bool {
        guard let direction = button.direction else { return false }
        return Focus.move(direction, within: element)
    }

    func close() {
        retrying?.cancel()
        Keys.release(self)
    }
}
