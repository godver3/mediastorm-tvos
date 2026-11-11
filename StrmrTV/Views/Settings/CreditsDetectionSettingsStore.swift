import Foundation

/// Settings › Playback › Credits Detection: this device's override of `creditsDetectionEnabled`
/// (nil follows the server: the device's admin setting, else the profile's; off by default), as
/// the other device settings override theirs.
@MainActor
final class CreditsDetectionSettingsStore: ObservableObject {
    static let shared = CreditsDetectionSettingsStore()

    /// On / off on this device; nil for Default.
    @Published var override: Bool? {
        didSet {
            if let override { defaults.set(override, forKey: Self.key) } else { defaults.removeObject(forKey: Self.key) }
        }
    }

    /// The server's value, shown as "Default (…)"; nil until read.
    @Published private(set) var serverValue: Bool?

    private let defaults = UserDefaults.standard
    private static let key = "strmrtv.creditsDetection"

    private init() {
        override = defaults.object(forKey: Self.key) as? Bool
    }

    func refresh() async {
        serverValue = await APIClient.shared.playbackSettings().creditsDetectionEnabled
    }

    /// Whether the player reads frames for credit text, given the server's value.
    func enabled(server: Bool) -> Bool { override ?? server }
}
