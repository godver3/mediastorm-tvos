import Foundation

/// Settings › Playback › Auto-play Trailers: this device's override of `autoPlayTrailersTV`
/// (nil follows the server: the device's admin setting, else the profile's), as the other
/// device settings override theirs.
@MainActor
final class TrailerSettingsStore: ObservableObject {
    static let shared = TrailerSettingsStore()

    /// On / off on this device; nil for Default.
    @Published var autoPlayOverride: Bool? {
        didSet {
            if let autoPlayOverride { defaults.set(autoPlayOverride, forKey: Self.key) } else { defaults.removeObject(forKey: Self.key) }
        }
    }

    /// The server's value, shown as "Default (…)"; nil until read.
    @Published private(set) var serverAutoPlay: Bool?

    private let defaults = UserDefaults.standard
    private static let key = "strmrtv.autoPlayTrailers"

    private init() {
        autoPlayOverride = defaults.object(forKey: Self.key) as? Bool
    }

    func refresh() async {
        serverAutoPlay = await APIClient.shared.playbackSettings().autoPlayTrailers
    }

    /// Whether details pages play the trailer behind the header, given the server's value.
    func autoPlay(server: Bool) -> Bool { autoPlayOverride ?? server }
}
