import Foundation

/// Just enough HTTP/1.1 for the editing page: one request per connection,
/// read in full and answered, then the connection closes. Everything the
/// network hands over is untrusted, so sizes are capped and anything odd is
/// refused rather than guessed at.
public struct HTTPRequest: Sendable, Equatable {
    public let method: String
    /// The path, without the query.
    public let path: String
    /// Header names in lower case.
    public let headers: [String: String]
    public let body: Data

    /// The most a request's headers may be, and its body.
    public static let longestHead = 8 * 1024
    public static let longestBody = 512 * 1024

    public enum Parse: Sendable, Equatable {
        /// Not all here yet: read more.
        case incomplete
        case complete(HTTPRequest)
        /// Answer with this status and close.
        case invalid(Int)
    }

    /// Reads a request from the bytes received so far.
    public static func parse(_ data: Data) -> Parse {
        let separator = Data("\r\n\r\n".utf8)
        guard let end = data.range(of: separator) else {
            return data.count > longestHead ? .invalid(431) : .incomplete
        }
        guard end.lowerBound <= longestHead,
              let head = String(data: data[data.startIndex..<end.lowerBound], encoding: .utf8) else { return .invalid(431) }
        let lines = head.components(separatedBy: "\r\n")
        let parts = lines[0].split(separator: " ", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[2].hasPrefix("HTTP/1."), parts[1].hasPrefix("/") else { return .invalid(400) }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { return .invalid(400) }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            guard !name.isEmpty, headers[name] == nil else { return .invalid(400) }
            headers[name] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        guard headers["transfer-encoding"] == nil else { return .invalid(501) }
        let length: Int
        if let text = headers["content-length"] {
            guard let value = Int(text), value >= 0 else { return .invalid(400) }
            length = value
        } else {
            length = 0
        }
        guard length <= longestBody else { return .invalid(413) }
        let bodyStart = end.upperBound
        guard data.distance(from: bodyStart, to: data.endIndex) >= length else { return .incomplete }
        let target = String(parts[1])
        let path = target.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? target
        return .complete(HTTPRequest(method: String(parts[0]), path: path, headers: headers,
                                     body: Data(data[bodyStart..<data.index(bodyStart, offsetBy: length)])))
    }
}

public struct HTTPResponse: Sendable, Equatable {
    public let status: Int
    public let contentType: String
    public let body: Data

    public init(status: Int, contentType: String = "text/plain; charset=utf-8", body: Data) {
        self.status = status
        self.contentType = contentType
        self.body = body
    }

    public static func text(_ status: Int, _ text: String) -> HTTPResponse {
        HTTPResponse(status: status, body: Data(text.utf8))
    }

    public static func json(_ value: some Encodable, status: Int = 200) -> HTTPResponse {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return HTTPResponse(status: status, contentType: "application/json; charset=utf-8",
                            body: (try? encoder.encode(value)) ?? Data("{}".utf8))
    }

    /// The bytes to send. Nothing is cached, nothing is sent on as a
    /// referrer, and the page may run only its own inline script and talk
    /// only to this Apple TV.
    public var serialized: Data {
        let reason = [200: "OK", 400: "Bad Request", 401: "Unauthorized", 403: "Forbidden", 404: "Not Found",
                      405: "Method Not Allowed", 408: "Request Timeout", 413: "Content Too Large",
                      422: "Unprocessable Content", 423: "Locked", 431: "Request Header Fields Too Large",
                      501: "Not Implemented"][status] ?? "Error"
        let head = [
            "HTTP/1.1 \(status) \(reason)",
            "Content-Type: \(contentType)",
            "Content-Length: \(body.count)",
            "Connection: close",
            "Cache-Control: no-store",
            "Referrer-Policy: no-referrer",
            "X-Content-Type-Options: nosniff",
            "X-Frame-Options: DENY",
            "Content-Security-Policy: default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; connect-src 'self'; form-action 'none'; frame-ancestors 'none'; base-uri 'none'",
        ].joined(separator: "\r\n")
        return Data((head + "\r\n\r\n").utf8) + body
    }
}
