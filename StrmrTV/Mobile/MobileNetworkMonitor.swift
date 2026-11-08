#if os(iOS)
import Foundation
import Network

/// The phone's network path (`NWPathMonitor`): whether there is one, which interface it uses
/// and whether it is expensive (cellular, a hotspot) or constrained (Low Data Mode). As in the
/// Expo app (`deviceNetworkState`), the device counts as offline only when the system says so
/// and still says so two seconds later, so a Wi-Fi to cellular handover isn't an outage.
@MainActor
final class MobileNetworkMonitor: ObservableObject {
    static let shared = MobileNetworkMonitor()

    enum Interface: String {
        case wifi, cellular, wired, other, none

        var title: String {
            switch self {
            case .wifi: String(localized: "Wi-Fi")
            case .cellular: String(localized: "Cellular")
            case .wired: String(localized: "Ethernet")
            case .other: String(localized: "Other")
            case .none: String(localized: "None")
            }
        }

        var symbol: String {
            switch self {
            case .wifi: "wifi"
            case .cellular: "antenna.radiowaves.left.and.right"
            case .wired: "cable.connector"
            case .other: "network"
            case .none: "wifi.slash"
            }
        }
    }

    struct Path: Equatable {
        var satisfied = true
        var interface: Interface = .other
        var isExpensive = false
        var isConstrained = false
        /// Wi-Fi is among the usable interfaces (it may not be the one in use).
        var hasWiFi = false
    }

    @Published private(set) var path = Path()
    /// Confirmed offline (no path for two seconds).
    @Published private(set) var isDeviceOffline = false
    /// Called on the main actor after the path changes (not for the first report).
    var onChange: ((Path) -> Void)?

    private var monitor: NWPathMonitor?
    private var confirmTask: Task<Void, Never>?
    private var reported = false
    private static let confirmDelay: Duration = .seconds(2)

    private init() {}

    func start() {
        guard monitor == nil else { return }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] nwPath in
            let next = Self.describe(nwPath)
            Task { @MainActor in self?.update(next) }
        }
        monitor.start(queue: DispatchQueue(label: "com.strmr.app.nx.mobile-path"))
        self.monitor = monitor
        #if DEBUG
        if DebugNetworkFault.current == .offline { update(Path(satisfied: false, interface: .none)) }
        if let until = DebugNetworkFault.until {
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(max(0, until.timeIntervalSinceNow) + 0.1))
                self?.refresh()
            }
        }
        #endif
    }

    /// The simulated fault changed (Debug): report the path again.
    func refresh() {
        guard let nwPath = monitor?.currentPath else { return }
        update(Self.describe(nwPath))
    }

    private func update(_ raw: Path) {
        var next = raw
        #if DEBUG
        if DebugNetworkFault.current == .offline { next = Path(satisfied: false, interface: .none) }
        #endif
        let first = !reported
        reported = true
        guard first || next != path else { return }
        path = next
        MobileReconnectJournal.record("network-state", [
            "connected": next.satisfied ? "true" : "false", "interface": next.interface.rawValue,
            "expensive": next.isExpensive ? "true" : "false", "constrained": next.isConstrained ? "true" : "false",
        ])
        if next.satisfied {
            confirmTask?.cancel()
            confirmTask = nil
            isDeviceOffline = false
        } else if confirmTask == nil {
            if first {
                isDeviceOffline = true
            } else {
                confirmTask = Task { [weak self] in
                    try? await Task.sleep(for: Self.confirmDelay)
                    guard !Task.isCancelled, let self else { return }
                    self.confirmTask = nil
                    if !self.path.satisfied {
                        self.isDeviceOffline = true
                        MobileReconnectJournal.record("device-offline-confirmed")
                    }
                }
            }
        }
        if !first { onChange?(next) }
    }

    nonisolated private static func describe(_ path: NWPath) -> Path {
        let interface: Interface
        if path.status != .satisfied {
            interface = .none
        } else if path.usesInterfaceType(.wifi) {
            interface = .wifi
        } else if path.usesInterfaceType(.cellular) {
            interface = .cellular
        } else if path.usesInterfaceType(.wiredEthernet) {
            interface = .wired
        } else {
            interface = .other
        }
        return Path(satisfied: path.status == .satisfied, interface: interface,
                    isExpensive: path.isExpensive, isConstrained: path.isConstrained,
                    hasWiFi: path.availableInterfaces.contains { $0.type == .wifi })
    }
}
#endif
