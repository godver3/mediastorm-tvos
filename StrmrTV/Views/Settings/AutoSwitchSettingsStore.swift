import Foundation

/// Settings › Playback › Auto Switch Sources: whether a movie or episode moves to another
/// source by itself when the server reports its source broken or too slow, or playback keeps
/// stalling (`PlayerViewController+AutoSwitch`). On unless turned off on this device.
@MainActor
final class AutoSwitchSettingsStore: ObservableObject {
    static let shared = AutoSwitchSettingsStore()

    @Published var enabled: Bool { didSet { defaults.set(enabled, forKey: Self.key) } }

    private let defaults = UserDefaults.standard
    private static let key = "strmrtv.autoSwitchSources"

    private init() {
        enabled = defaults.object(forKey: Self.key) as? Bool ?? true
    }
}
