/// Crockford base32: the digits, and the letters except I, L, O and U. Used
/// for the codes people type on a TV remote (`ScheduleCode`, channel codes
/// in `CustomChannel`). Typing is forgiving: lower case is fine, dashes and
/// spaces are ignored, O reads as 0, and I and L read as 1.
enum Crockford {
    static let alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")

    /// Each character's value (0 to 31), ignoring dashes and spaces. Nil if
    /// any other character isn't in the alphabet.
    static func digits(of text: String) -> [UInt8]? {
        var digits: [UInt8] = []
        for character in text.uppercased() where character != "-" && character != " " {
            let normalized: Character = switch character {
            case "O": "0"
            case "I", "L": "1"
            default: character
            }
            guard let digit = alphabet.firstIndex(of: normalized) else { return nil }
            digits.append(UInt8(digit))
        }
        return digits
    }

    /// `bytes`, five bits per character, in groups of five joined by dashes.
    static func encode(_ bytes: [UInt8]) -> String {
        var characters: [Character] = []
        var buffer = 0, bits = 0
        for byte in bytes {
            buffer = (buffer << 8 | Int(byte)) & 0xFFFF
            bits += 8
            while bits >= 5 {
                bits -= 5
                characters.append(alphabet[(buffer >> bits) & 31])
            }
        }
        if bits > 0 { characters.append(alphabet[(buffer << (5 - bits)) & 31]) }
        return grouped(characters)
    }

    /// The bytes `encode` made, or nil if `text` isn't a code. The last
    /// character's spare bits must be zero, so a typo there is caught too.
    static func decode(_ text: String) -> [UInt8]? {
        guard let digits = digits(of: text), !digits.isEmpty else { return nil }
        var bytes: [UInt8] = []
        var buffer = 0, bits = 0
        for digit in digits {
            buffer = (buffer << 5 | Int(digit)) & 0xFFFF
            bits += 5
            if bits >= 8 {
                bits -= 8
                bytes.append(UInt8((buffer >> bits) & 255))
            }
        }
        return buffer & ((1 << bits) - 1) == 0 ? bytes : nil
    }

    /// Groups of five characters joined by dashes, like `7KQM2-X9PDA`.
    static func grouped(_ characters: [Character]) -> String {
        stride(from: 0, to: characters.count, by: 5)
            .map { String(characters[$0..<min($0 + 5, characters.count)]) }
            .joined(separator: "-")
    }
}
