import Foundation

/// The last multiscreen selection, kept on this device per profile, for the Live tab's
/// Resume Multiscreen. A selection of fewer than two channels is never saved, so an earlier
/// one stays. (Expo saves it to the profile's `liveTV` settings, but the server's settings
/// model has no field for it and drops it; device-local by user decision.)
@MainActor
final class MultiscreenResume: ObservableObject {
    static let shared = MultiscreenResume()

    struct Selection: Codable, Equatable {
        /// In screen order.
        var channels: [LiveChannel]
        /// Which of `channels` plays its audio.
        var audioIndex: Int
    }

    enum Keys {
        static func selection(_ profile: String) -> String { "multiscreen.lastSelection.\(profile)" }
        /// Set the first time the "More screens, higher load" warning shows; it never shows again.
        static let warningShown = "multiscreen.loadWarningShown"
    }

    private let defaults: UserDefaults
    private let profile: () -> String
    /// Bumped on every save, so the Live menu offers Resume as soon as there is one.
    @Published private(set) var revision = 0

    init(defaults: UserDefaults = .standard, profile: @escaping () -> String = { APIClient.shared.profileID }) {
        self.defaults = defaults
        self.profile = profile
    }

    /// The active profile's saved selection, when it has two channels or more.
    var saved: Selection? {
        guard let data = defaults.data(forKey: Keys.selection(profile())),
              let selection = try? JSONDecoder().decode(Selection.self, from: data),
              selection.channels.count >= 2 else { return nil }
        return selection
    }

    func save(_ selection: Selection) {
        guard selection.channels.count >= 2, selection != saved,
              let data = try? JSONEncoder().encode(selection) else { return }
        defaults.set(data, forKey: Keys.selection(profile()))
        revision += 1
    }

    var warningShown: Bool {
        get { defaults.bool(forKey: Keys.warningShown) }
        set { defaults.set(newValue, forKey: Keys.warningShown) }
    }
}
