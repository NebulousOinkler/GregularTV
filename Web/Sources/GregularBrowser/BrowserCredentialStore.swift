import Foundation
import GregularCore
import GregularJellyfin
import JavaScriptEventLoop
import JavaScriptKit

/// The sign-ins in a browser: a `CredentialStore` kept encrypted in
/// IndexedDB (`js/vault.js`), never in plain local storage. The encryption
/// only keeps them from being read as they are: anyone with this browser
/// profile's files has the key too. So a sign-in can instead be kept for
/// this visit only (`rememberNextSignIn(_:)`), in memory, never written.
///
/// The browser's storage only answers asynchronously, and a store answers
/// at once, so it's read once at launch (`load()`) and held in memory;
/// each change is written behind, in order.
public final class BrowserCredentialStore: CredentialStore, @unchecked Sendable {
    private var credentials: [Credentials]
    /// The last write, which the next one waits for.
    private var writing: Task<Void, Never>?
    /// The sign-ins kept for this visit only, by `signInID`: never written.
    private var forThisVisit: Set<String> = []
    /// Whether the next sign-in saved is kept in the browser, or for this
    /// visit only; nil leaves it as it was.
    private var nextSignInRemembered: Bool?

    private init(credentials: [Credentials]) {
        self.credentials = credentials
    }

    /// The sign-ins saved in this browser. One that can't be read (another
    /// version's, or a damaged one) is left out.
    @MainActor public static func load() async -> BrowserCredentialStore {
        let text = try? await vault.load!().promised().string
        return BrowserCredentialStore(credentials: text.map { Credentials.list(from: Data($0.utf8)) } ?? [])
    }

    public func allCredentials() -> [Credentials] { credentials }

    /// Whether the next sign-in saved is kept in this browser (true), or
    /// only until the page closes (false). Nil takes back the choice, so
    /// saving a sign-in again (watching it) leaves it as it was.
    public func rememberNextSignIn(_ remember: Bool?) {
        nextSignInRemembered = remember
    }

    public func saveCredentials(_ credentials: Credentials) throws {
        if let remember = nextSignInRemembered {
            if remember { forThisVisit.remove(credentials.signInID) } else { forThisVisit.insert(credentials.signInID) }
            nextSignInRemembered = nil
        }
        self.credentials = self.credentials.using(credentials)
        write()
    }

    public func deleteCredentials(_ credentials: Credentials) throws {
        forThisVisit.remove(credentials.signInID)
        self.credentials = self.credentials.removing(credentials)
        write()
    }

    public func deleteAll() throws {
        credentials = []
        forThisVisit = []
        after { _ = try? await Self.vault.erase!().promised() }
    }

    /// Waits for every change so far to be written.
    public func settle() async {
        await writing?.value
    }

    private func write() {
        let remembered = credentials.filter { !forThisVisit.contains($0.signInID) }
        guard let json = try? JSONEncoder().encode(remembered), let text = String(data: json, encoding: .utf8) else { return }
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
}
