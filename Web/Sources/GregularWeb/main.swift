import JavaScriptEventLoop

// Swift's tasks and the main actor run on the browser's event loop.
JavaScriptEventLoop.installGlobalExecutor()
Task { @MainActor in await WebApp.start() }
