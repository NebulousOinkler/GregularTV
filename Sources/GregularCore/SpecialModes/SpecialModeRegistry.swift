import Foundation

/// Every special mode, and the keywords that open them, from
/// `Resources/special-modes.jsonc`. That file holds only the keywords'
/// hashes (`keywordHash(for:)`), so neither it nor the app built from it
/// gives the keywords away. The rest of the app only ever sees a `SpecialMode`.
///
/// **To add a special mode:**
/// 1. Hash each keyword: `swift run keyword-hash "THE KEYWORD"`.
/// 2. Add the mode to `special-modes.jsonc`:
///
///        { "modes": [ { "id": "example", "keywordHashes": ["…"], "library": "Example" } ] }
///
///    `library` is optional: without it, the mode plays from the whole library.
/// 3. In each front end that has screens for it, add them to its
///    `SpecialModeScreens` under the same id. A front end without them
///    doesn't accept its keywords, so they stay secret there.
///
/// Typing a keyword is forgiving, as with every code: any case, with or
/// without spaces and dashes. `swift test` checks the file.
public struct SpecialModeRegistry: Sendable {
    public enum LoadError: Error, Equatable, CustomStringConvertible {
        case duplicateMode(SpecialMode.ID)
        case noKeywords(SpecialMode.ID)
        case duplicateKeyword(String)
        /// Not 64 hex digits, as `keywordHash(for:)` makes.
        case notAHash(String)

        public var description: String {
            switch self {
            case .duplicateMode(let id): "special-modes.jsonc lists \(id) more than once"
            case .noKeywords(let id): "special-modes.jsonc gives \(id) no keyword hashes"
            case .duplicateKeyword(let hash): "special-modes.jsonc uses the keyword hash \(hash) more than once"
            case .notAHash(let text): "special-modes.jsonc's \(text) isn't a keyword hash (64 hex digits)"
            }
        }
    }

    /// Why a keyword can't be used.
    public enum KeywordProblem: Error, Equatable, CustomStringConvertible {
        /// Nothing but spaces and dashes.
        case empty
        /// It would never open its mode: what's typed is read as a schedule code first (`CodeEntry`).
        case isAScheduleCode

        public var description: String {
            switch self {
            case .empty: "A keyword needs letters or digits."
            case .isAScheduleCode: "That's also a schedule code (10 letters and digits), so it would never open a mode. Pick another."
            }
        }
    }

    /// Each keyword's hash, and the mode it opens.
    private let modesByHash: [String: SpecialMode]

    /// No special modes.
    public init() {
        modesByHash = [:]
    }

    private init(modesByHash: [String: SpecialMode]) {
        self.modesByHash = modesByHash
    }

    /// Every mode, in order of id.
    public var modes: [SpecialMode] {
        Set(modesByHash.values).sorted { $0.id.rawValue < $1.id.rawValue }
    }

    /// The mode `text` is a keyword for, if any.
    public func mode(forKeyword text: String) -> SpecialMode? {
        modesByHash[Self.hash(Self.normalized(text))]
    }

    /// Only the modes with these ids: those a front end has screens for.
    public func limited(to ids: Set<SpecialMode.ID>) -> SpecialModeRegistry {
        SpecialModeRegistry(modesByHash: modesByHash.filter { ids.contains($0.value.id) })
    }

    /// The hash `special-modes.jsonc` keeps for `keyword`: SHA-256, in hex,
    /// of "gregular-special-mode:" and the keyword in upper case without
    /// spaces or dashes (so typing it is forgiving).
    public static func keywordHash(for keyword: String) throws(KeywordProblem) -> String {
        let normalized = normalized(keyword)
        guard !normalized.isEmpty else { throw .empty }
        guard ScheduleCode(normalized) == nil else { throw .isAScheduleCode }
        return hash(normalized)
    }

    /// The modes that ship with the app (`Resources/special-modes.jsonc`, compiled in).
    public static func bundled() throws -> SpecialModeRegistry {
        try load(from: Data(PackageResources.special_modes_jsonc))
    }

    /// JSON, with lines starting `//` as comments.
    public static func load(from data: Data) throws -> SpecialModeRegistry {
        let json = String(decoding: data, as: UTF8.self)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        var modesByHash: [String: SpecialMode] = [:]
        var ids = Set<SpecialMode.ID>()
        for entry in try JSONDecoder().decode(File.self, from: Data(json.utf8)).modes {
            let mode = SpecialMode(id: entry.id, catalogue: entry.library.map { .library(named: $0) } ?? .wholeLibrary)
            guard ids.insert(mode.id).inserted else { throw LoadError.duplicateMode(mode.id) }
            guard !entry.keywordHashes.isEmpty else { throw LoadError.noKeywords(mode.id) }
            for hash in entry.keywordHashes.map({ $0.lowercased() }) {
                guard hash.count == 64, hash.allSatisfy(\.isHexDigit) else { throw LoadError.notAHash(hash) }
                guard modesByHash.updateValue(mode, forKey: hash) == nil else { throw LoadError.duplicateKeyword(hash) }
            }
        }
        return SpecialModeRegistry(modesByHash: modesByHash)
    }

    private struct File: Decodable {
        struct Mode: Decodable {
            let id: SpecialMode.ID
            let keywordHashes: [String]
            let library: String?
        }
        let modes: [Mode]
    }

    /// A keyword as typed, the way it's hashed: upper case, without the
    /// spaces and dashes codes ignore.
    private static func normalized(_ text: String) -> String {
        String(text.uppercased().filter { !Crockford.isSeparator($0) })
    }

    private static func hash(_ normalized: String) -> String {
        SHA256.hex("gregular-special-mode:" + normalized)
    }
}

extension SpecialMode.ID: Decodable {
    public init(from decoder: any Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
    }
}
