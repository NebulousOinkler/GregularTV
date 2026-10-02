import Foundation
import GregularCore
import GregularJellyfin
import JavaScriptEventLoop
import JavaScriptKit

/// The sign-ins in a browser: a `CredentialStore` kept encrypted in
/// IndexedDB (`js/vault.js`), never in plain local storage.
///
/// The browser's storage only answers asynchronously, and a store answers
/// at once, so it's read once at launch (`load()`) and held in memory;
/// each change is written behind, in order.
public final class BrowserCredentialStore: CredentialStore, @unchecked Sendable {
    private var credentials: [Credentials]
    /// The last write, which the next one waits for.
    private var writing: Task<Void, Never>?

    private init(credentials: [Credentials]) {
        self.credentials = credentials
    }

    /// The sign-ins saved in this browser. One that can't be read (another
    /// version's, or a damaged one) is left out.
    @MainActor public static func load() async -> BrowserCredentialStore {
        let text = try? await vault.load!().promised().string
        let saved = text.flatMap { try? JSONDecoder().decode([Lossy].self, from: Data($0.utf8)) } ?? []
        return BrowserCredentialStore(credentials: saved.compactMap(\.credentials))
    }

    public func allCredentials() -> [Credentials] { credentials }

    public func saveCredentials(_ credentials: Credentials) throws {
        self.credentials = self.credentials.using(credentials)
        write()
    }

    public func deleteCredentials(_ credentials: Credentials) throws {
        self.credentials = self.credentials.removing(credentials)
        write()
    }

    public func deleteAll() throws {
        credentials = []
        after { _ = try? await Self.vault.erase!().promised() }
    }

    /// Waits for every change so far to be written.
    public func settle() async {
        await writing?.value
    }

    private func write() {
        guard let json = try? JSONEncoder().encode(credentials), let text = String(data: json, encoding: .utf8) else { return }
        after { _ = try? await Self.vault.save!(text).promised() }
    }

    /// Runs `work` once the writes before it are done.
    private func after(_ work: @escaping @MainActor () async -> Void) {
        let previous = writing
        writing = Task { @MainActor in
            await previous?.value
            await work()
        }
    }

    @MainActor private static var vault: JSObject { JSObject.global.gregularVault.object! }

    /// One saved sign-in, or nil if it can't be read.
    private struct Lossy: Decodable {
        let credentials: Credentials?
        init(from decoder: any Decoder) throws {
            credentials = try? Credentials(from: decoder)
        }
    }
}
