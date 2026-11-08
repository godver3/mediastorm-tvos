#if DEBUG
import Foundation

/// Debug-only simulated network failure, for checking offline handling in the simulator
/// without touching the real server or the Mac's network. Every `APIClient` request fails
/// with the error while it is set.
/// - `-StrmrSimulateOffline N`: the device reports no network (iOS) and requests fail as
///   `notConnectedToInternet` for the first N seconds after launch (0: until switched off).
/// - `-StrmrSimulateUnreachable N`: the network is up but the server doesn't answer
///   (`cannotConnectToHost`) for the first N seconds (0: until switched off).
/// The iPhone's Connection settings can switch either at runtime.
enum DebugNetworkFault {
    enum Mode: String, CaseIterable { case none, offline, unreachable }

    nonisolated(unsafe) static var mode: Mode = launchMode
    nonisolated(unsafe) static var until: Date? = launchUntil

    static var current: Mode {
        if let until, Date() >= until { return .none }
        return mode
    }

    static var error: URLError? {
        switch current {
        case .none: nil
        case .offline: URLError(.notConnectedToInternet)
        case .unreachable: URLError(.cannotConnectToHost)
        }
    }

    static func set(_ mode: Mode) {
        self.mode = mode
        until = nil
    }

    private static var launchMode: Mode {
        let d = UserDefaults.standard
        if d.object(forKey: "StrmrSimulateOffline") != nil { return .offline }
        if d.object(forKey: "StrmrSimulateUnreachable") != nil { return .unreachable }
        return .none
    }

    private static var launchUntil: Date? {
        let d = UserDefaults.standard
        let key = d.object(forKey: "StrmrSimulateOffline") != nil ? "StrmrSimulateOffline" : "StrmrSimulateUnreachable"
        let seconds = d.double(forKey: key)
        return seconds > 0 ? Date().addingTimeInterval(seconds) : nil
    }
}
#endif
