import Foundation

/// Turns what someone types on the remote into a backend base URL, following the
/// Expo app's rules (`normaliseBackendUrl`): without a scheme, LAN hosts get
/// `http://` and port 7777, anything else `https://` with its own port; a trailing
/// `/api` is dropped because request paths already start with `/api`.
enum ServerAddress {
    static let defaultPort = 7777

    static func normalize(_ input: String) -> URL? {
        var text = input.filter { !$0.isWhitespace }
        guard !text.isEmpty else { return nil }

        if text.range(of: "^[A-Za-z][A-Za-z0-9+.-]*://", options: .regularExpression) == nil {
            let parts = text.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
            let hostPort = String(parts[0])
            let rest = parts.count > 1 ? "/" + parts[1] : ""
            let hasPort = hostPort.contains(":")
            let host = hasPort ? String(hostPort.split(separator: ":")[0]) : hostPort
            let local = isLocal(host)
            let authority = hasPort || !local ? hostPort : "\(hostPort):\(defaultPort)"
            text = "\(hasPort || local ? "http" : "https")://\(authority)\(rest)"
        }

        guard var comps = URLComponents(string: text),
              let scheme = comps.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = comps.host, !host.isEmpty
        else { return nil }
        comps.scheme = scheme
        comps.host = host.lowercased()
        var path = comps.path
        while path.hasSuffix("/") { path.removeLast() }
        if path.lowercased().hasSuffix("/api") { path.removeLast(4) }
        comps.path = path
        comps.query = nil
        comps.fragment = nil
        comps.user = nil
        comps.password = nil
        return comps.url
    }

    /// Private IPv4 ranges, localhost, `.local` and bare (dot-less) hostnames.
    static func isLocal(_ host: String) -> Bool {
        let h = host.lowercased()
        if h == "localhost" || h.hasSuffix(".local") || !h.contains(".") { return true }
        let octets = h.split(separator: ".").compactMap { Int($0) }
        guard octets.count == 4 else { return false }
        switch (octets[0], octets[1]) {
        case (10, _), (127, _), (192, 168): return true
        case (172, 16...31): return true
        default: return false
        }
    }

    /// Short form for display: drops the scheme and a trailing slash.
    static func display(_ url: URL) -> String {
        var s = url.absoluteString
        for prefix in ["http://", "https://"] where s.hasPrefix(prefix) { s.removeFirst(prefix.count) }
        return s.hasSuffix("/") ? String(s.dropLast()) : s
    }
}
