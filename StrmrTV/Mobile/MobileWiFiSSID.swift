#if os(iOS)
import CoreLocation
import Foundation
import NetworkExtension

/// The current Wi-Fi network's name, for telling home from away. iOS shows it only to apps
/// with the Access Wi-Fi Information entitlement whose user allowed location access (the
/// Expo app asks for the same permission, with the same purpose string). Nil without either,
/// off Wi-Fi, and always in the simulator.
@MainActor
final class MobileWiFiSSID: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = MobileWiFiSSID()

    @Published private(set) var authorization: CLAuthorizationStatus
    private let manager = CLLocationManager()
    private var waiters: [CheckedContinuation<Void, Never>] = []
    /// Asked once per launch at most, as in the Expo app.
    private var askedThisLaunch = false

    private override init() {
        authorization = manager.authorizationStatus
        super.init()
        manager.delegate = self
    }

    var isAllowed: Bool { authorization == .authorizedWhenInUse || authorization == .authorizedAlways }
    var canAsk: Bool { authorization == .notDetermined }

    /// The SSID, asking for location access first when `ask` and it was never asked.
    func current(ask: Bool = false) async -> String? {
        if ask, canAsk, !askedThisLaunch { await requestAccess() }
        guard isAllowed else { return nil }
        let network = await NEHotspotNetwork.fetchCurrent()
        guard let ssid = network?.ssid, !ssid.isEmpty, ssid != "<unknown ssid>" else { return nil }
        return ssid
    }

    /// Shows the system location prompt (from Connection settings, or once on launch when
    /// switching between two addresses depends on it).
    func requestAccess() async {
        guard canAsk else { return }
        askedThisLaunch = true
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
            manager.requestWhenInUseAuthorization()
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorization = status
            guard status != .notDetermined else { return }
            let waiting = self.waiters
            self.waiters = []
            waiting.forEach { $0.resume() }
        }
    }
}
#endif
