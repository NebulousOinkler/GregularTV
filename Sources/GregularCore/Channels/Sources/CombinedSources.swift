import Foundation

/// Sources that combine other sources, so a channel can say "comedy or the
/// series Taskmaster, but nothing tagged Christmas":
///
/// ```json
/// "source": { "type": "all-of", "sources": [
///   { "type": "any-of", "sources": [
///     { "type": "genre", "anyOf": ["Comedy"] },
///     { "type": "series", "anyOf": ["Taskmaster"] } ] },
///   { "type": "not", "source": { "type": "tag", "anyOf": ["Christmas"] } } ] }
/// ```
///
/// They nest to any depth, and each inner source is any source type,
/// combined ones included.

/// Matches what every one of its sources matches (AND). With none, everything.
struct AllOfSource: ChannelSource {
    static let type = "all-of"
    let sources: [any ChannelSource]

    func matches(_ item: MediaItem) -> Bool {
        sources.allSatisfy { $0.matches(item) }
    }
}

/// Matches what any one of its sources matches (OR). With none, nothing.
struct AnyOfSource: ChannelSource {
    static let type = "any-of"
    let sources: [any ChannelSource]

    func matches(_ item: MediaItem) -> Bool {
        sources.contains { $0.matches(item) }
    }
}

/// Matches what its source doesn't (NOT).
struct NotSource: ChannelSource {
    static let type = "not"
    let source: any ChannelSource

    func matches(_ item: MediaItem) -> Bool {
        !source.matches(item)
    }
}

// MARK: - Decoding

private enum CombinedKeys: String, CodingKey {
    case sources, source
}

extension AllOfSource {
    init(from decoder: any Decoder) throws {
        sources = try ChannelSourceRegistry.decodeList(forKey: .sources, in: decoder.container(keyedBy: CombinedKeys.self))
    }
}

extension AnyOfSource {
    init(from decoder: any Decoder) throws {
        sources = try ChannelSourceRegistry.decodeList(forKey: .sources, in: decoder.container(keyedBy: CombinedKeys.self))
    }
}

extension NotSource {
    init(from decoder: any Decoder) throws {
        source = try ChannelSourceRegistry.decode(from: decoder.container(keyedBy: CombinedKeys.self).superDecoder(forKey: .source))
    }
}

extension ChannelSourceRegistry {
    private enum TypeKey: String, CodingKey {
        case type
    }

    /// A source of whichever type its `"type"` names.
    static func decode(from decoder: any Decoder) throws -> any ChannelSource {
        let container = try decoder.container(keyedBy: TypeKey.self)
        let name = try container.decode(String.self, forKey: .type)
        guard let type = sourceType(named: name) else {
            let known = all.map { $0.type }.joined(separator: ", ")
            throw DecodingError.dataCorruptedError(forKey: .type, in: container,
                                                   debugDescription: "Unknown source type '\(name)'. Known: \(known)")
        }
        return try type.init(from: decoder)
    }

    fileprivate static func decodeList(forKey key: CombinedKeys,
                                       in container: KeyedDecodingContainer<CombinedKeys>) throws -> [any ChannelSource] {
        var list = try container.nestedUnkeyedContainer(forKey: key)
        var sources: [any ChannelSource] = []
        while !list.isAtEnd {
            sources.append(try decode(from: list.superDecoder()))
        }
        return sources
    }
}
