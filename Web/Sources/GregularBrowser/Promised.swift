import JavaScriptEventLoop
import JavaScriptKit

extension JSValue {
    /// Waits for this promise, on the main actor. JavaScript values aren't
    /// `Sendable`, but the browser runs everything on one thread, so one can
    /// safely come back to the main actor.
    @MainActor public func promised() async throws -> JSValue {
        try await Promised.wait(for: Promised(value: self)).value
    }
}

/// A JavaScript value carried across an await (see `JSValue.promised()`).
struct Promised: @unchecked Sendable {
    let value: JSValue

    nonisolated static func wait(for promise: Promised) async throws -> Promised {
        guard let object = promise.value.object else { return promise }
        return Promised(value: try await JSPromise(unsafelyWrapping: object).value)
    }
}
