import Foundation
import GregularCore
import GregularJellyfin
import JavaScriptEventLoop
import JavaScriptFoundationCompat
import JavaScriptKit

/// The app's network path in a browser: every request it makes goes
/// through `fetch()`. (Video is fetched by the player, `VideoDeck`.)
///
/// It follows `TransportRules`, more strictly than it asks:
/// - **no redirects at all** (`redirect: "error"`): a browser can't show
///   where one goes before following it, so none is followed;
/// - a reply is read as it arrives and stopped once it's larger than
///   `TransportRules.largestResponse`;
/// - nothing is stored: no cookies or saved logins (`credentials: "omit"`),
///   no HTTP cache (`cache: "no-store"`), and no referrer is sent.
///
/// Plain http to a server on the home network is marked as such
/// (`targetAddressSpace: "local"`), so Chrome asks for permission to reach
/// the local network instead of blocking it as mixed content.
public struct FetchTransport: HTTPTransport {
    public init() {}

    public func send(_ request: ServerRequest) async throws -> ServerReply {
        try await Self.fetch(request)
    }

    @MainActor private static func fetch(_ request: ServerRequest) async throws -> ServerReply {
        let controller = JSObject.global.AbortController.function!.new()
        let options = Self.options(for: request)
        options["signal"] = controller.signal
        let fetch = JSObject.global.fetch.function!
        // Carried into the cancellation handler (see `Promised`).
        let pending = Promised(value: fetch(request.url.absoluteString, options))
        let abort = Promised(value: controller.jsValue)
        let response: JSObject
        do {
            response = try await withTaskCancellationHandler {
                try await Promised.wait(for: pending)
            } onCancel: {
                Task { @MainActor in _ = abort.value.abort() }
            }.value.object!
        } catch {
            throw Self.failure(error)
        }
        let status = Int(response.status.number ?? 0)
        // A size the server announces up front is turned down before anything arrives.
        if let length = response.headers.object?.get!("content-length").string.flatMap(Int.init),
           length > TransportRules.largestResponse {
            _ = controller.abort!()
            throw JellyfinError.responseTooLarge
        }
        let body = try await Self.read(response, abortingWith: controller)
        // Not followed, so a reply always comes from where it was sent.
        return ServerReply(url: request.url, status: status, body: body)
    }

    /// `fetch()`'s options for `request`.
    @MainActor static func options(for request: ServerRequest) -> JSObject {
        let options = JSObject()
        options["method"] = .string(request.method)
        let headers = JSObject()
        for (name, value) in request.headers { headers[name] = .string(value) }
        options["headers"] = .object(headers)
        if let body = request.body { options["body"] = body.jsValue }
        options["redirect"] = "error"
        options["credentials"] = "omit"
        options["cache"] = "no-store"
        options["referrerPolicy"] = "no-referrer"
        if BrowserNetwork.isLocalHTTP(request.url) { options["targetAddressSpace"] = "local" }
        return options
    }

    /// The reply's body, a chunk at a time, stopped once it's over the limit.
    @MainActor private static func read(_ response: JSObject, abortingWith controller: JSObject) async throws -> Data {
        guard let stream = response.body.object else { return Data() }
        let reader = stream.getReader!().object!
        var data = Data()
        while true {
            let chunk: JSObject
            do {
                chunk = try await reader.read!().promised().object!
            } catch {
                throw Self.failure(error)
            }
            if chunk.done.boolean == true { return data }
            data.append(Data.construct(from: chunk.value) ?? Data())
            if data.count > TransportRules.largestResponse {
                _ = reader.cancel!()
                _ = controller.abort!()
                throw JellyfinError.responseTooLarge
            }
        }
    }

    /// What a failed `fetch()` means. The browser doesn't say why (an
    /// unreachable server, a refused redirect, CORS and mixed content all
    /// look the same), so the message covers the likely causes.
    private static func failure(_ error: any Error) -> any Error {
        if error is CancellationError { return error }
        if let exception = error as? JSException, exception.thrownValue.object?.name.string == "AbortError" {
            return CancellationError()
        }
        return BrowserNetwork.Unreachable()
    }
}

/// What the browser allows of the network.
public enum BrowserNetwork {
    /// Plain http to a server on the home network (but not this computer,
    /// which browsers already treat as secure).
    public static func isLocalHTTP(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "http", let host = url.host()?.lowercased() else { return false }
        let loopback = host == "localhost" || host.hasSuffix(".localhost") || host.hasPrefix("127.") || host == "::1" || host == "[::1]"
        return !loopback && ServerAddress.isOnLocalNetwork(host)
    }

    /// A request the browser couldn't make.
    public struct Unreachable: LocalizedError {
        public init() {}

        public var errorDescription: String? {
            "Couldn't reach your server from this browser. Check the address, and that the server is switched on. "
                + "A server on plain http:// works only in Chrome or Edge, on your home network."
        }
    }
}
