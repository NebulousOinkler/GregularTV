import Foundation
import GregularCore
import JavaScriptKit

/// `AppPreferences`' storage in a browser: its local storage, under keys
/// starting "gregular.". The app's only use of local storage
/// (scripts/privacy-check.sh). If the browser won't keep anything (some
/// private windows), preferences last until the page closes.
public final class BrowserPreferences: PreferenceStorage, @unchecked Sendable {
    private static let prefix = "gregular."
    /// Used when local storage can't be.
    private var fallback: [String: Stored] = [:]

    public init() {}

    public func object(forKey key: String) -> Any? {
        let stored = read(key).flatMap { try? JSONDecoder().decode(Stored.self, from: Data($0.utf8)) } ?? fallback[key]
        return stored?.value
    }

    public func set(_ value: Any?, forKey key: String) {
        guard let value else {
            fallback[key] = nil
            _ = try? Self.storage?.throwing.removeItem!(Self.prefix + key)
            return
        }
        guard let stored = Stored(value), let json = try? JSONEncoder().encode(stored),
              let text = String(data: json, encoding: .utf8) else { return }
        fallback[key] = stored
        _ = try? Self.storage?.throwing.setItem!(Self.prefix + key, text)
    }

    /// Forgets every preference this app keeps in the browser.
    public func removeAll() {
        fallback = [:]
        guard let storage = Self.storage, let count = storage.length.number else { return }
        let keys = (0..<Int(count)).compactMap { storage.key!($0).string }.filter { $0.hasPrefix(Self.prefix) }
        for key in keys { _ = try? storage.throwing.removeItem!(key) }
    }

    private func read(_ key: String) -> String? {
        (try? Self.storage?.throwing.getItem!(Self.prefix + key))?.string
    }

    /// Local storage, or nil where the browser refuses it.
    private static var storage: JSObject? {
        let reflect = JSObject.global.Reflect.object!
        return (try? reflect.throwing.get!(JSObject.global, "localStorage"))?.object
    }

    /// One preference, as kept: what `AppPreferences` stores.
    private enum Stored: Codable {
        case int(Int), bool(Bool), string(String), strings([String])

        init?(_ value: Any) {
            switch value {
            case let value as Bool: self = .bool(value)
            case let value as Int: self = .int(value)
            case let value as String: self = .string(value)
            case let value as [String]: self = .strings(value)
            default: return nil
            }
        }

        var value: Any {
            switch self {
            case .int(let value): value
            case .bool(let value): value
            case .string(let value): value
            case .strings(let value): value
            }
        }
    }
}
