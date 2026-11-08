import Foundation

#if os(iOS)
/// Network routes (iOS): which address requests go to as the phone moves between the home
/// network, other networks and the iroh tunnel. `MobileNetworkMonitor` picks the route.
extension AppSession {
    /// The address saved by Change Server; network switching never overwrites it.
    var savedServerURL: URL? { defaults.url(forKey: Key.serverURL) }

    /// Paired, on the home network: requests go straight to the verified LAN address.
    func routeHomeDirect(_ url: URL) {
        isRemote = false
        isHomeDirect = true
        api.remoteCredential = nil
        serverURL = url
        api.baseURL = url
    }

    /// Back onto the iroh tunnel. The bridge is sticky: if it can't start, requests go to an
    /// unreachable loopback address rather than silently to the LAN.
    func routeRemoteTunnel() async throws {
        isHomeDirect = false
        isRemote = true
        api.remoteCredential = RemoteAccess.shared.pairing?.credential
        do {
            try await reconnectRemoteOrThrow()
        } catch {
            if serverURL?.host() != "127.0.0.1" {
                serverURL = Self.unreachableLoopback
                api.baseURL = Self.unreachableLoopback
            }
            throw error
        }
    }

    /// Direct (unpaired) server: the home or away address from the server's network settings,
    /// used until the network changes; not saved.
    func routeNetworkURL(_ url: URL) {
        guard !isRemote, !isHomeDirect else { return }
        serverURL = url
        api.baseURL = url
    }

    private static let unreachableLoopback = URL(string: "http://127.0.0.1:9")!
}
#endif

