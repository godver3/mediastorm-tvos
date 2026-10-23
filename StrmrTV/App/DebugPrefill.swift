#if DEBUG
import Foundation

/// Optional local test values for the simulator and UI tests. A gitignored
/// `Secrets.swift` (copy `Secrets.example.swift.txt`) provides them; it is looked up
/// at runtime, so the app builds the same with or without it.
protocol DebugSecretsProviding {
    static var serverURL: String { get }
    static var username: String { get }
    static var password: String { get }
    static var profileName: String { get }
    static var profilePIN: String { get }
}

/// Debug-only launch switches (pass as `-Key 1` launch arguments):
/// - `StrmrResetSession`: forget the server, Keychain session and last profile.
/// - `StrmrAutoSignIn`: run server → login → profile from `Secrets` without UI.
/// - `StrmrDryRunHide`: "Hide from Continue Watching" updates the UI but never calls
///   the server, so UI tests can exercise it without changing the profile.
/// - `StrmrAutoPlayTrailers`: details pages autoplay the backdrop trailer whatever the
///   profile's `autoPlayTrailersTV` says.
/// - `StrmrPairCode <code>`: with `StrmrAutoSignIn`, pair over iroh remote access with that
///   connection code first (when not already paired).
/// - `StrmrEnableShelves <id,id>`: Home shows those rows even when the profile has them off.
/// With `Secrets` present the onboarding fields are prefilled either way.
enum DebugPrefill {
    static var secrets: DebugSecretsProviding.Type? {
        NSClassFromString("StrmrTVDebugSecrets") as? DebugSecretsProviding.Type
    }

    static var resetSession: Bool { UserDefaults.standard.bool(forKey: "StrmrResetSession") }
    static var autoSignIn: Bool { UserDefaults.standard.bool(forKey: "StrmrAutoSignIn") }
    static var dryRunHide: Bool { UserDefaults.standard.bool(forKey: "StrmrDryRunHide") }
    static var pairCode: String? { UserDefaults.standard.string(forKey: "StrmrPairCode") }
    static var enabledShelves: Set<String> {
        Set((UserDefaults.standard.string(forKey: "StrmrEnableShelves") ?? "").split(separator: ",").map(String.init))
    }
    static var autoPlayTrailers: Bool { UserDefaults.standard.bool(forKey: "StrmrAutoPlayTrailers") }
}
#endif
