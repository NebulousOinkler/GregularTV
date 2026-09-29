import Foundation
import GregularCore
/// How this app introduces itself to Jellyfin in every request.
///
/// The device name is the kind of device, from whichever app uses this
/// (the Apple TV app says "Apple TV"), never the name the user gave their
/// device, which often contains a person's name.
public struct ClientIdentity: Sendable, Equatable {
    public static let clientName = "Gregular TV"
    public static let clientVersion = "1.0.0"

    public let deviceID: String
    public let deviceName: String

    /// - Parameter deviceName: the kind of device, such as "Apple TV".
    public init(deviceID: String, deviceName: String) {
        self.deviceID = deviceID
        self.deviceName = deviceName
    }

    /// The value of the `Authorization` header Jellyfin expects.
    public func authorizationHeader(token: String?) -> String {
        var fields = [
            ("Client", Self.clientName),
            ("Device", deviceName),
            ("DeviceId", deviceID),
            ("Version", Self.clientVersion),
        ]
        if let token { fields.append(("Token", token)) }
        return "MediaBrowser " + fields
            .map { "\($0.0)=\"\(Self.sanitize($0.1))\"" }
            .joined(separator: ", ")
    }

    /// Quotes and commas would break the header format, and a line break
    /// or other control character could start a header of its own.
    private static func sanitize(_ value: String) -> String {
        value.filter { character in
            character != "\"" && character != ","
                && !character.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
        }
    }
}
