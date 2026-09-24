/// How this app introduces itself to Jellyfin in every request.
///
/// The device name is deliberately generic ("Apple TV"), not the name the
/// user gave their Apple TV, which often contains a person's name.
public struct ClientIdentity: Sendable, Equatable {
    public static let clientName = "Gregular TV"
    public static let clientVersion = "1.0.0"

    public let deviceID: String
    public let deviceName: String

    public init(deviceID: String, deviceName: String = "Apple TV") {
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

    /// Quotes and commas would break the header format.
    private static func sanitize(_ value: String) -> String {
        value.filter { $0 != "\"" && $0 != "," }
    }
}
