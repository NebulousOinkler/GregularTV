/// Another way of watching, opened by typing one of its keywords where a
/// schedule code goes (`CodeEntry`). Undocumented on purpose: nothing on
/// screen mentions one until it's open.
///
/// The logic knows only which mode it is and where its programmes come
/// from. What it looks like and does is up to each front end, which finds
/// its screens by `id` (see `SpecialModeRegistry`).
public struct SpecialMode: Sendable, Hashable, Identifiable {
    /// Names a mode in `special-modes.jsonc`, and its screens in each front end.
    public struct ID: RawRepresentable, Sendable, Hashable, ExpressibleByStringLiteral, CustomStringConvertible {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public init(stringLiteral value: String) { rawValue = value }
        public var description: String { rawValue }
    }

    /// Where a mode's programmes come from. Always the server's library:
    /// all of it, or one library on it.
    public enum Catalogue: Sendable, Hashable {
        /// Everything the channels could play.
        case wholeLibrary
        /// Only the videos in the library (a `MediaLibrary` collection) called this.
        case library(named: String)
    }

    public let id: ID
    public let catalogue: Catalogue

    public init(id: ID, catalogue: Catalogue = .wholeLibrary) {
        self.id = id
        self.catalogue = catalogue
    }
}
