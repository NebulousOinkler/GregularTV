import Foundation
import GregularJellyfin
import JavaScriptKit

/// A file fetched whole into the browser's memory, never to disk, by the
/// same rules as every other request (`FetchTransport`): no cookies, no
/// cache, no redirects, and stopped once it's larger than asked. It's held
/// as a `Blob`, in the browser rather than WebAssembly, so a long video
/// doesn't fill the app's own memory.
public enum WholeFile {
    /// The file at `url`, as a `Blob`. Throws if it can't be fetched, if the
    /// server refuses, if it's larger than `mostBytes`, or when the task is
    /// cancelled (which stops the fetch).
    @MainActor public static func fetch(_ url: URL, mostBytes: Int) async throws -> JSObject {
        let (response, controller) = try await FetchTransport.start(ServerRequest(url: url), largest: mostBytes)
        switch Int(response.status.number ?? 0) {
        case 200..<300: break
        case 401: throw JellyfinError.unauthorized
        case let status: throw JellyfinError.httpStatus(status)
        }
        let chunks = JSObject.global.Array.function!.new()
        try await FetchTransport.read(response, largest: mostBytes, abortingWith: controller) { chunk in
            _ = chunks.push!(chunk)
        }
        let options = JSObject()
        options["type"] = .string(response.headers.object?.get!("content-type").string ?? "")
        return JSObject.global.Blob.function!.new(chunks, options)
    }
}
