import GregularBrowser
import JavaScriptEventLoop

// Times in the viewer's own time zone, set before anything reads it.
BrowserTimeZone.adopt()
// Swift's tasks and the main actor run on the browser's event loop.
JavaScriptEventLoop.installGlobalExecutor()
Task { @MainActor in await WebApp.start() }
