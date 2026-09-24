/// Decides which items belong on a channel.
///
/// A source is a filter over the in-memory library. It's decoded from the
/// `"source"` object in `channels.json`, where `"type"` picks the source type
/// and the remaining keys are that type's fields.
///
/// **To add a source type:**
/// 1. Create a `Decodable` type in `Channels/Sources/` that conforms to
///    `ChannelSource`.
/// 2. Add it to `ChannelSourceRegistry.all`.
public protocol ChannelSource: Sendable, Decodable {
    /// The `"type"` value used in `channels.json`, e.g. `"genre"`.
    static var type: String { get }

    func matches(_ item: MediaItem) -> Bool
}

public enum ChannelSourceRegistry {
    public static var all: [any ChannelSource.Type] {
        [
            AllItemsSource.self,
            GenreSource.self,
            SeriesSource.self,
            YearRangeSource.self,
            TagSource.self,
            // ← add new source types here
        ]
    }

    public static func sourceType(named name: String) -> (any ChannelSource.Type)? {
        all.first { $0.type == name }
    }
}
