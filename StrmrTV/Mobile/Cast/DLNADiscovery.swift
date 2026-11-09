#if os(iOS)
import Darwin
import Foundation

/// A UPnP MediaRenderer found on the LAN, with the control URLs its description names.
struct DLNARenderer: Sendable, Hashable {
    struct Service: Sendable, Hashable {
        let type: String
        let controlURL: URL
    }

    /// The device's UDN (`uuid:…`).
    let udn: String
    let name: String
    let model: String?
    let host: String
    let avTransport: Service
    let renderingControl: Service?
    let connectionManager: Service?

    var device: CastDevice {
        CastDevice(id: "dlna:\(udn)", name: name, model: model, kind: .dlna, address: host)
    }
}

/// SSDP discovery, as the Expo app's bridge does it: an `M-SEARCH` for
/// `urn:schemas-upnp-org:device:MediaRenderer:1` to the multicast group with `MX: 3`, plus the
/// same search sent unicast to every renderer seen before (and to an address typed in by hand),
/// then each reply's description fetched for its name and AVTransport / RenderingControl URLs.
///
/// The unicast probes matter on iOS: without Apple's multicast entitlement the system may drop
/// the group send, and a renderer answers a unicast `M-SEARCH` all the same.
enum DLNADiscovery {
    private static let log = AppLog(category: "dlna")
    private static let knownHostsKey = "dlna.knownHosts"
    /// Replies spread over the `MX: 3` window; hanging up earlier drops late ones.
    static let window: TimeInterval = 3

    /// Renderers seen before, probed by unicast on every search.
    static var knownHosts: [String] {
        get { UserDefaults.standard.stringArray(forKey: knownHostsKey) ?? [] }
        set { UserDefaults.standard.set(Array(Set(newValue)).sorted(), forKey: knownHostsKey) }
    }

    /// Searches the network and returns every renderer whose description could be read.
    static func discover() async -> [DLNARenderer] {
        let replies = await search(multicast: true, unicast: knownHosts)
        let renderers = await describe(replies)
        if !renderers.isEmpty { knownHosts += renderers.map(\.host) }
        return renderers
    }

    /// A renderer at an address typed in by hand (`192.168.1.42`).
    static func probe(host: String) async throws -> DLNARenderer {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        var address = in_addr()
        guard inet_pton(AF_INET, trimmed, &address) == 1 else {
            throw CastError(String(localized: "Enter an IPv4 address, such as 192.168.1.42."))
        }
        let replies = await search(multicast: false, unicast: [trimmed])
        guard let renderer = await describe(replies).first else {
            throw CastError(String(localized: "No DLNA renderer answered at \(trimmed)."))
        }
        knownHosts += [renderer.host]
        return renderer
    }

    // MARK: SSDP

    struct Reply: Hashable, Sendable {
        let location: URL
        let usn: String
    }

    private static func search(multicast: Bool, unicast: [String]) async -> [Reply] {
        await Task.detached(priority: .userInitiated) {
            runSearch(multicast: multicast, unicast: unicast)
        }.value
    }

    private static func message(host: String) -> String {
        "M-SEARCH * HTTP/1.1\r\nHOST: \(host):1900\r\nMAN: \"ssdp:discover\"\r\nMX: 3\r\n"
            + "ST: urn:schemas-upnp-org:device:MediaRenderer:1\r\n\r\n"
    }

    /// Blocking: one UDP socket, the sends, then replies until the window closes.
    private nonisolated static func runSearch(multicast: Bool, unicast: [String]) -> [Reply] {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { return [] }
        defer { close(fd) }
        var timeout = timeval(tv_sec: 0, tv_usec: 200_000)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var ttl: UInt8 = 2
        setsockopt(fd, IPPROTO_IP, IP_MULTICAST_TTL, &ttl, socklen_t(MemoryLayout<UInt8>.size))

        func send(to host: String) {
            var address = sockaddr_in()
            address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            address.sin_family = sa_family_t(AF_INET)
            address.sin_port = UInt16(1900).bigEndian
            guard inet_pton(AF_INET, host, &address.sin_addr) == 1 else { return }
            let bytes = Array(message(host: host).utf8)
            let sent = withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    sendto(fd, bytes, bytes.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            if sent < 0 { log.info("SSDP send to \(host) failed: errno \(errno)") }
        }
        // Sent now and again a second in: UDP is best effort, and the first datagrams after the
        // app starts were seen to go unanswered (a missed search is a missing TV).
        func sendAll() {
            if multicast { send(to: "239.255.255.250") }
            unicast.forEach(send)
        }
        sendAll()
        var resent = false

        var replies = Set<Reply>()
        var buffer = [UInt8](repeating: 0, count: 8192)
        let deadline = Date().addingTimeInterval(window)
        while Date() < deadline, replies.count < 64 {
            if !resent, deadline.timeIntervalSinceNow < window - 1 {
                resent = true
                sendAll()
            }
            let count = recv(fd, &buffer, buffer.count, 0)
            guard count > 0 else { continue }
            if let reply = parse(String(decoding: buffer[0..<count], as: UTF8.self)) { replies.insert(reply) }
        }
        return Array(replies)
    }

    /// An `HTTP/1.1 200 OK` search reply for a MediaRenderer, with its description URL.
    private nonisolated static func parse(_ datagram: String) -> Reply? {
        var headers: [String: String] = [:]
        for line in datagram.components(separatedBy: "\r\n").dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            headers[name] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        let target = (headers["st"] ?? headers["nt"] ?? "").lowercased()
        guard target.contains("mediarenderer"), let location = headers["location"].flatMap(URL.init(string:)),
              location.scheme == "http" else { return nil }
        return Reply(location: location, usn: headers["usn"] ?? location.absoluteString)
    }

    // MARK: Descriptions

    private static func describe(_ replies: [Reply]) async -> [DLNARenderer] {
        let locations = Array(Set(replies.map(\.location)))
        let found = await withTaskGroup(of: DLNARenderer?.self) { group in
            for location in locations {
                group.addTask { await description(at: location) }
            }
            var renderers: [DLNARenderer] = []
            for await renderer in group {
                if let renderer { renderers.append(renderer) }
            }
            return renderers
        }
        // One per device: a renderer answering on two interfaces (or twice) is listed once.
        var seen = Set<String>()
        return found.filter { seen.insert($0.udn).inserted }.sorted { $0.name < $1.name }
    }

    private static func description(at location: URL) async -> DLNARenderer? {
        var request = URLRequest(url: location, timeoutInterval: 5)
        request.setValue("MediaStorm/1.0 UPnP/1.0 DLNADOC/1.50", forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let root = XMLTree.parse(data) else {
            log.info("DLNA description unreadable: \(location.host ?? "?")")
            return nil
        }
        return renderer(from: root, location: location)
    }

    /// The first MediaRenderer device in a description (the root device, or one embedded in it).
    static func renderer(from root: XMLTree.Node, location: URL) -> DLNARenderer? {
        let base = root.child("URLBase").flatMap { URL(string: $0.text.castTrimmed) } ?? location
        guard let device = root.descendants("device").first(where: {
            $0.child("deviceType")?.text.lowercased().contains("mediarenderer") == true
        }) else { return nil }
        let services = device.child("serviceList")?.children ?? []
        func service(_ name: String) -> DLNARenderer.Service? {
            guard let node = services.first(where: { $0.child("serviceType")?.text.contains(":service:\(name):") == true }),
                  let type = node.child("serviceType")?.text.castTrimmed,
                  let path = node.child("controlURL")?.text.castTrimmed,
                  let url = URL(string: path, relativeTo: base)?.absoluteURL else { return nil }
            return .init(type: type, controlURL: url)
        }
        guard let avTransport = service("AVTransport"), let host = location.host else { return nil }
        let name = device.child("friendlyName")?.text.castTrimmed ?? host
        return DLNARenderer(udn: device.child("UDN")?.text.castTrimmed ?? location.absoluteString,
                            name: name.isEmpty ? host : name,
                            model: device.child("modelName")?.text.castTrimmed,
                            host: host, avTransport: avTransport,
                            renderingControl: service("RenderingControl"),
                            connectionManager: service("ConnectionManager"))
    }
}
#endif
