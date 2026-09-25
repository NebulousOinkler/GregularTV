import Foundation
import GregularCore

/// Jellyfin's JSON uses PascalCase keys (`RunTimeTicks`, `SeriesId`). These
/// coders map them to Swift's camelCase (`runTimeTicks`, `seriesId`), so the
/// DTOs don't each need a `CodingKeys` enum.
enum JellyfinJSON {
    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .custom { path in
            Key(path.last!.stringValue.changingFirstLetter { $0.lowercased() })
        }
        return decoder
    }

    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .custom { path in
            Key(path.last!.stringValue.changingFirstLetter { $0.uppercased() })
        }
        return encoder
    }

    private struct Key: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init(_ string: String) { stringValue = string }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }
}

private extension String {
    func changingFirstLetter(_ transform: (String) -> String) -> String {
        guard let first else { return self }
        return transform(String(first)) + dropFirst()
    }
}

/// Jellyfin measures time in "ticks" of 100 nanoseconds.
enum Ticks {
    static let perSecond: Double = 10_000_000

    static func seconds(_ ticks: Int64) -> TimeInterval { Double(ticks) / perSecond }
}
