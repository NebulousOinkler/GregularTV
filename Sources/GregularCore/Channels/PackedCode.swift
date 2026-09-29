import Foundation

/// The short codes typed to share things between Apple TVs (a custom
/// channel's code, a household's set-times code): a version byte, the
/// fields, then a check byte (CRC-8) so a mistyped code is rejected rather
/// than read wrongly, all in Crockford base32 (see `Crockford`).
struct CodeWriter {
    /// The most UTF-8 bytes one text in a code holds (its length is a byte).
    static let longestText = 255
    private var bytes: [UInt8]

    init(version: UInt8) {
        bytes = [version]
    }

    mutating func byte(_ value: UInt8) {
        bytes.append(value)
    }

    /// Two bytes: a year, or minutes after midnight.
    mutating func number(_ value: Int) {
        bytes += [UInt8(truncatingIfNeeded: value >> 8), UInt8(truncatingIfNeeded: value)]
    }

    /// A name, in full: a series or film name must match the library
    /// exactly. Only one longer than `longestText` bytes is cut short, at
    /// the end of a character, so the code still reads.
    mutating func text(_ value: String) {
        var text = Substring(value)
        while text.utf8.count > Self.longestText { text = text.dropLast() }
        bytes.append(UInt8(text.utf8.count))
        bytes += Array(text.utf8)
    }

    /// Set times, without their time zone (the code carries one for all).
    mutating func setTimes(_ programmes: [FixedProgramme]) {
        byte(UInt8(clamping: programmes.count))
        for entry in programmes.prefix(255) {
            let (isItem, name) = switch entry.match {
            case .series(let name): (false, name)
            case .item(let name): (true, name)
            }
            byte((isItem ? 1 : 0) | (entry.exclusive ? 2 : 0))
            text(name)
            byte(entry.weekdays.reduce(0) { $0 | UInt8(1 << ($1 - 1)) })
            byte(UInt8(clamping: entry.dates.count))
            for date in entry.dates.sorted(by: { ($0.month, $0.day) < ($1.month, $1.day) }).prefix(255) {
                byte(UInt8(date.month))
                byte(UInt8(date.day))
            }
            byte(UInt8(clamping: entry.times.count))
            for time in entry.times.prefix(255) { number(time) }
        }
    }

    var code: String {
        Crockford.encode(bytes + [Self.check(bytes)])
    }

    /// CRC-8: catches any single mistyped character, and most others.
    static func check(_ bytes: [UInt8]) -> UInt8 {
        bytes.reduce(UInt8(0)) { crc, byte in
            (0..<8).reduce(crc ^ byte) { c, _ in c & 0x80 != 0 ? (c << 1) ^ 0x07 : c << 1 }
        }
    }
}

/// Reads what `CodeWriter` wrote.
struct CodeReader {
    private let bytes: [UInt8]
    private var offset = 1

    /// Nil unless `code` is a code of this `version` with a matching check byte.
    init?(code: String, version: UInt8) {
        guard let all = Crockford.decode(code), all.count >= 3, CodeWriter.check(Array(all.dropLast())) == all.last,
              all[0] == version else { return nil }
        bytes = Array(all.dropLast())
    }

    var isAtEnd: Bool { offset == bytes.count }

    mutating func byte() -> UInt8? {
        guard offset < bytes.count else { return nil }
        defer { offset += 1 }
        return bytes[offset]
    }

    mutating func number() -> Int? {
        guard let high = byte(), let low = byte() else { return nil }
        return Int(high) << 8 | Int(low)
    }

    mutating func text() -> String? {
        guard let length = byte().map(Int.init), offset + length <= bytes.count else { return nil }
        defer { offset += length }
        return String(bytes: bytes[offset..<(offset + length)], encoding: .utf8)
    }

    mutating func setTimes() -> [FixedProgramme]? {
        guard let count = byte() else { return nil }
        var entries: [FixedProgramme] = []
        for _ in 0..<count {
            guard let flags = byte(), let name = text(), let weekdayBits = byte(), let dateCount = byte() else { return nil }
            var dates = Set<FixedProgramme.MonthDay>()
            for _ in 0..<dateCount {
                guard let month = byte(), let day = byte() else { return nil }
                dates.insert(FixedProgramme.MonthDay(month: Int(month), day: Int(day)))
            }
            guard let timeCount = byte() else { return nil }
            var times: [Int] = []
            for _ in 0..<timeCount {
                guard let time = number() else { return nil }
                times.append(time)
            }
            entries.append(FixedProgramme(match: flags & 1 != 0 ? .item(name) : .series(name), times: times,
                                          weekdays: Set((1...7).filter { weekdayBits & UInt8(1 << ($0 - 1)) != 0 }),
                                          dates: dates, exclusive: flags & 2 != 0))
        }
        return entries
    }
}
