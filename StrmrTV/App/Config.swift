import Foundation
import UIKit

/// Per-install identity and build info. Server, account and profile are chosen at
/// runtime (see `AppSession`); nothing here is environment-specific.
enum Config {
    /// Stable per-install client ID, sent as X-Client-ID and registered with
    /// `POST /api/clients/register` so the backend's per-device settings and Active
    /// Streams can tell this client apart. Never rotated, including on sign-out.
    static let clientID: String = {
        let key = "strmrtv.clientID"
        if let existing = UserDefaults.standard.string(forKey: key) { return existing }
        let fresh = "strmrtv-" + UUID().uuidString.lowercased()
        UserDefaults.standard.set(fresh, forKey: key)
        return fresh
    }()

    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    static var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }

    static let deviceType = "Apple TV"

    @MainActor
    static var osVersion: String { "tvOS \(UIDevice.current.systemVersion)" }

    /// `version+build`, as registration and log uploads report it.
    static var fullVersion: String { "\(appVersion)+\(buildNumber)" }

    /// Payload for `POST /api/clients/register`. Nickname is left out so routine
    /// re-registration never overwrites one set in the admin UI.
    @MainActor
    static func registration(profileID: String) -> [String: Any] {
        [
            "id": clientID,
            "userId": profileID,
            "deviceName": UIDevice.current.name,
            "deviceType": deviceType,
            "os": osVersion,
            "appVersion": fullVersion,
        ]
    }
}
