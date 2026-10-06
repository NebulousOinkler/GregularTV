import Darwin
import Foundation
import GregularScreens
import Network
import Observation

/// Serves a page on the home network (`LocalPage`: the editing page,
/// karaoke's song picker) while it's wanted: started when its screen or
/// switch turns it on, stopped when it's off again.
/// It only accepts connections from private, link-local or loopback
/// addresses (`LocalPage.isLocal`), at most `mostConnections` at once,
/// reads one request per connection, capped in size and time, and closes. (Network's own `acceptLocalOnly`
/// isn't used: in the tvOS simulator it refused every connection, even
/// from the same Mac.)
@MainActor @Observable
final class LocalPageServer {
    enum Status: Equatable {
        case starting
        /// Reachable at these addresses ("http://192.168.1.20:8080").
        case ready([String])
        case failed(String)
    }

    private(set) var status: Status = .starting
    private(set) var page: LocalPage?

    @ObservationIgnored private var listener: NWListener?
    @ObservationIgnored private let queue = DispatchQueue(label: "tv.gregular.local-page")
    /// The port to try first, easy to type; another is used if it's taken.
    static let preferredPort: NWEndpoint.Port = 8080
    /// How long a connection may take to send its request.
    nonisolated static let requestTimeout: TimeInterval = 10
    /// The most connections open at once. More are refused, so a device on
    /// the network can't fill the app's memory with half-sent requests.
    nonisolated static let mostConnections = 8

    /// Connections open now. Only touched on `queue`.
    private final class OpenConnections: @unchecked Sendable {
        var count = 0
    }
    @ObservationIgnored private let open = OpenConnections()

    /// Starts serving the page `makePage` makes for this Apple TV's addresses (with the port).
    func start(_ makePage: @escaping @MainActor (Set<String>) -> LocalPage) {
        guard listener == nil else { return }
        listen(makePage, on: Self.preferredPort)
    }

    func stop() {
        listener?.cancel()
        listener = nil
        page = nil
        status = .starting
    }

    private func listen(_ makePage: @escaping @MainActor (Set<String>) -> LocalPage, on port: NWEndpoint.Port) {
        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = false
        parameters.allowLocalEndpointReuse = true
        guard let listener = try? NWListener(using: parameters, on: port) else {
            if port != .any { return listen(makePage, on: .any) }
            status = .failed("The page couldn't start.")
            return
        }
        self.listener = listener
        listener.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in self?.update(state, makePage: makePage, triedPort: port) }
        }
        let queue = queue, open = open
        listener.newConnectionHandler = { [weak self] connection in
            guard case .hostPort(let host, _) = connection.endpoint, case let address = Self.text(of: host),
                  LocalPage.isLocal(address), open.count < Self.mostConnections else {
                return connection.cancel()
            }
            open.count += 1
            connection.stateUpdateHandler = { state in
                if case .cancelled = state { open.count -= 1 }
            }
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + Self.requestTimeout) { connection.cancel() }
            Task { @MainActor in
                guard let page = self?.page else { return Self.send(.text(503, "The page isn't on."), on: connection) }
                Self.receive(on: connection, from: address, page: page, buffer: Data())
            }
        }
        listener.start(queue: queue)
    }

    private func update(_ state: NWListener.State, makePage: @escaping @MainActor (Set<String>) -> LocalPage,
                        triedPort: NWEndpoint.Port) {
        switch state {
        case .ready:
            guard let port = listener?.port?.rawValue else { return }
            let addresses = Self.localAddresses()
            guard !addresses.isEmpty else {
                status = .failed("This Apple TV isn't on a network the page can be reached from.")
                return
            }
            page = makePage(Set(addresses.map { "\($0):\(port)" }))
            status = .ready(addresses.map { "http://\($0):\(port)" })
        case .failed:
            listener?.cancel()
            listener = nil
            if triedPort != .any {
                listen(makePage, on: .any)
            } else {
                status = .failed("The page couldn't start. Check that the Apple TV is on your home network.")
            }
        default:
            break
        }
    }

    /// Reads until a whole request is in, then answers it and closes.
    private nonisolated static func receive(on connection: NWConnection, from address: String, page: LocalPage, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { data, _, isComplete, error in
            var buffer = buffer
            if let data { buffer.append(data) }
            switch HTTPRequest.parse(buffer) {
            case .incomplete:
                if isComplete || error != nil { return connection.cancel() }
                receive(on: connection, from: address, page: page, buffer: buffer)
            case .invalid(let status):
                Self.send(.text(status, "Bad request."), on: connection)
            case .complete(let request):
                Task { @MainActor in
                    Self.send(await page.handle(request, from: address), on: connection)
                }
            }
        }
    }

    private nonisolated static func send(_ response: HTTPResponse, on connection: NWConnection) {
        connection.send(content: response.serialized, contentContext: .finalMessage, isComplete: true,
                        completion: .contentProcessed { _ in connection.cancel() })
    }

    /// An address as text, without any interface ("%en0").
    private nonisolated static func text(of host: NWEndpoint.Host) -> String {
        switch host {
        case .ipv4(let address): "\(address)"
        case .ipv6(let address): "\(address)"
        case .name(let name, _): name
        @unknown default: ""
        }
    }

    /// This Apple TV's IPv4 addresses on its network interfaces (Wi-Fi and
    /// Ethernet), as a phone on the same network would reach it.
    static func localAddresses() -> [String] {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return [] }
        defer { freeifaddrs(list) }
        var addresses: [String] = []
        for interface in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let flags = Int32(interface.pointee.ifa_flags)
            guard let address = interface.pointee.ifa_addr, address.pointee.sa_family == UInt8(AF_INET),
                  flags & IFF_UP != 0, flags & IFF_RUNNING != 0, flags & IFF_LOOPBACK == 0,
                  String(cString: interface.pointee.ifa_name).hasPrefix("en") else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0
            else { continue }
            let text = String(decoding: host.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            if !text.hasPrefix("169.254."), !addresses.contains(text) { addresses.append(text) }
        }
        return addresses
    }
}
