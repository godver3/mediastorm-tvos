#if os(iOS)
import Foundation

/// The server's "Network URL Switching" settings (admin UI → Server), as the Expo app reads
/// them: this device's own (`/api/clients/{id}/settings`, top level), else the profile's
/// (`network` in `/api/users/{id}/settings`), else the server's (`network` in `/api/settings`),
/// whichever section first names a home Wi-Fi. Cached for launches that can't reach the server.
struct MobileNetworkSettings: Codable, Equatable {
    enum Source: String, Codable { case device, profile, server }

    var homeWifiSSID = ""
    var homeBackendURL = ""
    var remoteBackendURL = ""
    var source: Source = .server

    var isConfigured: Bool { !homeWifiSSID.isEmpty && (!homeBackendURL.isEmpty || !remoteBackendURL.isEmpty) }

    /// The home address as a base URL (no `/api`), unless it is missing or a loopback.
    var homeURL: URL? { Self.address(homeBackendURL) }
    var remoteURL: URL? { Self.address(remoteBackendURL) }

    private static func address(_ text: String) -> URL? {
        guard let url = ServerAddress.normalize(text), let host = url.host()?.lowercased() else { return nil }
        if ["localhost", "::1", "0.0.0.0"].contains(host) || host.hasPrefix("127.") { return nil }
        return url
    }

    // MARK: Store

    private static let cacheKey = "strmr.mobile.networkSettings"

    static var cached: MobileNetworkSettings? {
        UserDefaults.standard.data(forKey: cacheKey).flatMap { try? JSONDecoder().decode(Self.self, from: $0) }
    }

    /// Nil clears the cache (no section names a home network).
    static func cache(_ settings: MobileNetworkSettings?) {
        if let settings, let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: cacheKey)
        } else {
            UserDefaults.standard.removeObject(forKey: cacheKey)
        }
    }

    /// The effective section from the server, or nil when none names a home Wi-Fi. Throws when
    /// nothing answered, so a failed fetch keeps the cache.
    @MainActor
    static func fetch() async throws -> MobileNetworkSettings? {
        struct Fields: Decodable {
            let homeWifiSSID: String?
            let homeBackendUrl: String?
            let remoteBackendUrl: String?
        }
        struct Nested: Decodable { let network: Fields? }
        let api = APIClient.shared
        async let device: Fields? = try? await api.send("GET", "/api/clients/\(APIClient.segment(Config.clientID))/settings",
                                                        query: ["userId": api.profileID], promptOnLock: false, timeout: 10)
        async let profile: Nested? = try? await api.send("GET", "\(api.profilePath)/settings", promptOnLock: false, timeout: 10)
        async let server: Nested? = try? await api.send("GET", "/api/settings", promptOnLock: false, timeout: 10)
        let (d, p, s) = await (device, profile, server)
        guard d != nil || p != nil || s != nil else { throw URLError(.cannotConnectToHost) }
        let candidates: [(Fields?, Source)] = [(d, .device), (p?.network, .profile), (s?.network, .server)]
        for (fields, source) in candidates {
            let ssid = fields?.homeWifiSSID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !ssid.isEmpty, let fields else { continue }
            return MobileNetworkSettings(
                homeWifiSSID: ssid,
                homeBackendURL: fields.homeBackendUrl?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                remoteBackendURL: fields.remoteBackendUrl?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                source: source)
        }
        return nil
    }
}
#endif
