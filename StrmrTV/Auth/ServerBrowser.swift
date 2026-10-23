import Foundation
import Network

/// A MediaStorm server advertised over Bonjour (`_mediastorm._tcp` in `local.`).
struct DiscoveredServer: Identifiable, Equatable {
    let id: String
    /// TXT `name`, else the service instance name.
    let name: String
    /// TXT `version`.
    let version: String?
    /// TXT `apiPath` (e.g. `/api`, or `/base/api` behind a reverse proxy).
    let apiPath: String
    let endpoint: NWEndpoint

    static func == (a: Self, b: Self) -> Bool {
        a.id == b.id && a.name == b.name && a.version == b.version && a.apiPath == b.apiPath
    }
}

/// Browses the LAN for MediaStorm servers while the server screen is up, and turns
/// a pick into a base URL (`http://<IPv4>:<port><apiPath minus /api>`).
@MainActor
final class ServerBrowser: ObservableObject {
    static let serviceType = "_mediastorm._tcp"

    @Published private(set) var servers: [DiscoveredServer] = []

    private var browser: NWBrowser?

    func start() {
        guard browser == nil else { return }
        let params = NWParameters()
        params.includePeerToPeer = false
        let browser = NWBrowser(for: .bonjourWithTXTRecord(type: Self.serviceType, domain: "local."), using: params)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            let found = results.compactMap(Self.server(from:)).sorted {
                $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
            Task { @MainActor in self?.servers = found }
        }
        browser.stateUpdateHandler = { state in
            // Local Network denied or Bonjour unavailable: stay quiet, manual entry works.
            if case let .failed(error) = state { print("[ServerBrowser] browse failed: \(error)") }
            if case let .waiting(error) = state { print("[ServerBrowser] browse waiting: \(error)") }
        }
        browser.start(queue: .main)
        self.browser = browser
    }

    func stop() {
        browser?.cancel()
        browser = nil
    }

    private nonisolated static func server(from result: NWBrowser.Result) -> DiscoveredServer? {
        guard case let .service(instance, _, _, _) = result.endpoint else { return nil }
        var txt: [String: String] = [:]
        if case let .bonjour(record) = result.metadata { txt = record.dictionary }
        func value(_ key: String) -> String? {
            txt[key].map { $0.trimmingCharacters(in: .whitespaces) }.flatMap { $0.isEmpty ? nil : $0 }
        }
        var apiPath = value("apiPath") ?? "/api"
        if !apiPath.hasPrefix("/") { apiPath = "/" + apiPath }
        return DiscoveredServer(
            id: instance,
            name: value("name") ?? instance,
            version: value("version"),
            apiPath: apiPath,
            endpoint: result.endpoint
        )
    }

    // MARK: Resolution

    /// Resolves the service to an address, preferring IPv4 (link-local IPv6 needs a
    /// zone that URLs handle badly), and builds the server's base URL.
    nonisolated static func baseURL(for server: DiscoveredServer) async -> URL? {
        let resolved: (host: String, port: UInt16)?
        if let v4 = await resolve(server.endpoint, ipv4Only: true) {
            resolved = v4
        } else {
            resolved = await resolve(server.endpoint, ipv4Only: false)
        }
        guard let resolved else { return nil }
        return ServerAddress.normalize("http://\(resolved.host):\(resolved.port)\(server.apiPath)")
    }

    /// Opens a TCP connection to the Bonjour endpoint and reads the address it
    /// reached; nil on failure or after `timeout`.
    private nonisolated static func resolve(_ endpoint: NWEndpoint, ipv4Only: Bool, timeout: TimeInterval = 4) async -> (host: String, port: UInt16)? {
        let params = NWParameters.tcp
        if ipv4Only, let ip = params.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options {
            ip.version = .v4
        }
        let connection = NWConnection(to: endpoint, using: params)
        let once = ResumeOnce<(host: String, port: UInt16)?>()
        return await withCheckedContinuation { continuation in
            once.continuation = continuation
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    var answer: (String, UInt16)?
                    if case let .hostPort(host, port)? = connection.currentPath?.remoteEndpoint,
                       let text = hostString(host) {
                        answer = (text, port.rawValue)
                    }
                    once.resume(answer)
                    connection.cancel()
                case .failed, .waiting:
                    once.resume(nil)
                    connection.cancel()
                case .cancelled:
                    once.resume(nil)
                default:
                    break
                }
            }
            connection.start(queue: .global(qos: .userInitiated))
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                once.resume(nil)
                connection.cancel()
            }
        }
    }

    private nonisolated static func hostString(_ host: NWEndpoint.Host) -> String? {
        switch host {
        case let .ipv4(address):
            return stripZone("\(address)")
        case let .ipv6(address):
            if let mapped = address.asIPv4 { return stripZone("\(mapped)") }
            return "[\(stripZone("\(address)"))]"
        case let .name(name, _):
            return name
        @unknown default:
            return nil
        }
    }

    private nonisolated static func stripZone(_ text: String) -> String {
        text.split(separator: "%", maxSplits: 1).first.map(String.init) ?? text
    }
}

/// Resumes a continuation exactly once from whichever callback gets there first.
private final class ResumeOnce<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    var continuation: CheckedContinuation<Value, Never>?

    func resume(_ value: Value) {
        lock.lock()
        let c = continuation
        continuation = nil
        lock.unlock()
        c?.resume(returning: value)
    }
}
