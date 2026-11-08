#if os(iOS)
import Foundation

/// Chooses how the phone reaches the server, following the Expo app (`connectionSelection`,
/// `networkUrl`):
/// - Paired over iroh with a home network configured: the home address is used only once it
///   proves to be the paired server (`/api/remote-access/identity` answers with the invite's
///   endpoint id, within 2 s, without credentials). The Wi-Fi name is only a hint: a different,
///   readable SSID skips the probe; an unreadable one still probes. Otherwise the tunnel; the
///   bridge is sticky and never falls back to an unverified LAN address.
/// - A typed server with a home network configured: on the home Wi-Fi the home address, on
///   another Wi-Fi or on cellular the away address; on Wi-Fi with an unreadable name, the last
///   name-based answer from the past five minutes, else the address in use is kept.
@MainActor
final class MobileConnectionSelector: ObservableObject {
    static let shared = MobileConnectionSelector()

    enum Route: Equatable {
        case direct, homeDirect, remote, homeNetwork, awayNetwork
    }

    @Published private(set) var settings: MobileNetworkSettings? = MobileNetworkSettings.cached
    /// The last Wi-Fi name read (nil: unreadable or off Wi-Fi).
    @Published private(set) var lastSSID: String?
    /// Whether the last check found the phone on its home network (nil: couldn't tell).
    @Published private(set) var isHomeNetwork: Bool?
    @Published private(set) var lastChecked: Date?

    private var running: Task<Void, Never>?
    private let session = AppSession.shared
    private static let lastDetectionKey = "strmr.mobile.lastDetectedNetwork"

    /// A home network that can take over from the tunnel: paired, with a home Wi-Fi and address.
    var automaticHome: (url: URL, ssid: String, serverID: String)? {
        guard let settings, !settings.homeWifiSSID.isEmpty, let url = settings.homeURL,
              let invite = RemoteAccess.shared.pairing?.invite, let id = Self.serverID(invite: invite)
        else { return nil }
        return (url, settings.homeWifiSSID, id)
    }

    // MARK: Settings

    /// Re-reads the network settings (once signed in) and re-selects when they changed.
    func refreshSettings() async {
        guard session.phase == .ready else { return }
        let fetched: MobileNetworkSettings?
        do { fetched = try await MobileNetworkSettings.fetch() } catch { return }
        MobileNetworkSettings.cache(fetched)
        guard fetched != settings else { return }
        settings = fetched
        MobileReconnectJournal.record("network-settings-changed", ["configured": fetched?.isConfigured == true ? "true" : "false"])
        await select(reason: "settings changed")
    }

    // MARK: Selection

    /// Startup on a paired phone: the verified home address, when there is one.
    func verifiedHomeURL() async -> URL? {
        guard let home = automaticHome, !MobileNetworkMonitor.shared.isDeviceOffline,
              await shouldProbe(homeSSID: home.ssid),
              await Self.probeIdentity(home.url, expected: home.serverID)
        else { return nil }
        MobileReconnectJournal.record("route-home-direct", ["reason": "startup"])
        isHomeNetwork = true
        lastChecked = Date()
        return home.url
    }

    /// Re-evaluates the route. Joins a run in progress, except that a network change restarts it.
    func select(reason: String) async {
        if let running {
            if reason == "network change" || reason == "settings changed" { running.cancel() } else { return await running.value }
        }
        let task = Task { await run(reason: reason) }
        running = task
        await task.value
        if running == task { running = nil }
    }

    private func run(reason: String) async {
        guard !MobileNetworkMonitor.shared.isDeviceOffline, session.serverURL != nil || RemoteAccess.shared.pairing != nil else { return }
        // A playing title keeps its route; recovery (retry, failure) may still move it.
        let mayMove = !PlaybackCoordinator.shared.isPresentingPlayer || ["startup", "retry", "network failure"].contains(reason)
        if RemoteAccess.shared.pairing != nil {
            await selectPaired(reason: reason, mayMove: mayMove)
        } else if mayMove {
            await selectDirect(reason: reason)
        }
        lastChecked = Date()
    }

    private func selectPaired(reason: String, mayMove: Bool) async {
        var useHome = false
        if let home = automaticHome, await shouldProbe(homeSSID: home.ssid) {
            useHome = await Self.probeIdentity(home.url, expected: home.serverID)
        }
        guard !Task.isCancelled, mayMove else { return }
        isHomeNetwork = automaticHome == nil ? nil : useHome
        if useHome, let home = automaticHome {
            guard !session.isHomeDirect || session.serverURL != home.url else { return }
            session.routeHomeDirect(home.url)
            MobileReconnectJournal.record("route-home-direct", ["reason": reason])
        } else if session.isHomeDirect || !session.isRemote || reason != "periodic" {
            do {
                try await session.routeRemoteTunnel()
                MobileReconnectJournal.record("route-remote", ["reason": reason])
            } catch {
                MobileReconnectJournal.record("route-remote-failed", ["reason": reason, "error": error.localizedDescription])
            }
        }
    }

    private func selectDirect(reason: String) async {
        guard let settings, settings.isConfigured else { return }
        let path = MobileNetworkMonitor.shared.path
        // Asking is worth it only when the answer picks between two addresses.
        let ask = settings.homeURL != nil && settings.remoteURL != nil
        let ssid = await MobileWiFiSSID.shared.current(ask: ask)
        lastSSID = ssid
        let target: URL?
        if let ssid {
            let home = ssid.caseInsensitiveCompare(settings.homeWifiSSID) == .orderedSame
            isHomeNetwork = home
            Self.saveDetection(home: home)
            target = home ? settings.homeURL : settings.remoteURL
        } else if path.interface == .cellular, !path.hasWiFi {
            // Off Wi-Fi: away from home (a stale "home" answer must not keep the LAN address).
            isHomeNetwork = false
            Self.saveDetection(home: nil)
            target = settings.remoteURL
        } else if let recent = Self.recentDetection() {
            isHomeNetwork = recent
            target = recent ? settings.homeURL : settings.remoteURL
        } else {
            // Wi-Fi of unknown name: keep the address in use.
            isHomeNetwork = nil
            target = nil
        }
        guard !Task.isCancelled, let target, target != session.serverURL else { return }
        session.routeNetworkURL(target)
        MobileReconnectJournal.record(isHomeNetwork == true ? "route-home-network" : "route-away-network", ["reason": reason])
    }

    private func shouldProbe(homeSSID: String) async -> Bool {
        let ssid = await MobileWiFiSSID.shared.current()
        lastSSID = ssid
        return ssid == nil || ssid?.caseInsensitiveCompare(homeSSID) == .orderedSame
    }

    // MARK: Detection cache

    private static func saveDetection(home: Bool?) {
        if let home {
            UserDefaults.standard.set(["home": home, "at": Date().timeIntervalSince1970], forKey: lastDetectionKey)
        } else {
            UserDefaults.standard.removeObject(forKey: lastDetectionKey)
        }
    }

    /// A name-based answer from the past five minutes.
    private static func recentDetection() -> Bool? {
        guard let saved = UserDefaults.standard.dictionary(forKey: lastDetectionKey),
              let home = saved["home"] as? Bool, let at = saved["at"] as? TimeInterval,
              Date().timeIntervalSince1970 - at < 300
        else { return nil }
        return home
    }

    // MARK: Probes

    /// The iroh endpoint id inside an invite (`mshost-iroh-` + base64url JSON with `id`).
    static func serverID(invite: String) -> String? {
        guard invite.hasPrefix("mshost-iroh-") else { return nil }
        var encoded = String(invite.dropFirst("mshost-iroh-".count))
            .replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while encoded.count % 4 != 0 { encoded += "=" }
        guard let data = Data(base64Encoded: encoded),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = json["id"] as? String, id.count == 64, id.allSatisfy(\.isHexDigit)
        else { return nil }
        return id.lowercased()
    }

    /// Whether `base` is the paired server: no credentials go to an unverified address.
    static func probeIdentity(_ base: URL, expected: String) async -> Bool {
        #if DEBUG
        if DebugNetworkFault.error != nil { return false }
        #endif
        var req = URLRequest(url: base.appending(path: "/api/remote-access/identity"))
        req.timeoutInterval = 2
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.httpShouldHandleCookies = false
        let session = URLSession(configuration: .ephemeral, delegate: NoRedirects(), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        struct Identity: Decodable { let serverId: String? }
        guard let (data, response) = try? await session.data(for: req),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let identity = try? JSONDecoder().decode(Identity.self, from: data)
        else { return false }
        return identity.serverId?.lowercased() == expected
    }

    private final class NoRedirects: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest) async -> URLRequest? { nil }
    }
}
#endif
