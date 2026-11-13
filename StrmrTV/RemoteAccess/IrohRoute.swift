import Foundation

/// How the iroh link reaches the server: straight to it, through a relay, or not known yet.
enum IrohRoute: Equatable {
    case direct, relay, detecting

    /// The bridge's path diagnostics, `{"selectedPath":"direct"|"relay"|"unknown",…}`.
    init(diagnostics: [String: Any]) {
        switch diagnostics["selectedPath"] as? String {
        case "direct": self = .direct
        case "relay": self = .relay
        default: self = .detecting
        }
    }

    /// The live route, from the bridge.
    static func current() async -> IrohRoute {
        IrohRoute(diagnostics: await IrohBridge.pathDiagnostics())
    }

    /// Settings polls this often while the route is on screen (as the Expo app does).
    static let pollInterval: Duration = .seconds(2)

    var label: String {
        switch self {
        case .direct: String(localized: "Direct")
        case .relay: String(localized: "Relay")
        case .detecting: String(localized: "Detecting…")
        }
    }

    var systemImage: String {
        switch self {
        case .direct: "bolt.fill"
        case .relay: "cloud"
        case .detecting: "arrow.triangle.2.circlepath"
        }
    }
}
