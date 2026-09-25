import Foundation
import GregularCore

public enum ServerAddress {
    /// The URLs to try, in order, for what the user typed. Typing "https://"
    /// with a TV remote is tedious, so when no scheme is given we try https
    /// first, then http (common for LAN servers on port 8096).
    public static func candidates(for input: String) -> [URL] {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains("://") { return normalize(trimmed).map { [$0] } ?? [] }
        return ["https://", "http://"].compactMap { normalize($0 + trimmed) }
    }

    /// Turns what the user typed into a server base URL.
    ///
    /// `"192.168.1.5:8096"` becomes `http://192.168.1.5:8096`, and
    /// `"https://media.example.com/jellyfin/"` becomes
    /// `https://media.example.com/jellyfin`. A reverse-proxy sub-path is kept.
    /// Returns nil for input that isn't an http(s) address.
    public static func normalize(_ input: String) -> URL? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.contains("://") { text = "http://" + text }

        guard var components = URLComponents(string: text),
              let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = components.host, !host.isEmpty
        else { return nil }

        components.scheme = scheme
        components.query = nil
        components.fragment = nil
        components.user = nil
        components.password = nil
        while components.path.hasSuffix("/") { components.path.removeLast() }
        return components.url
    }
}
