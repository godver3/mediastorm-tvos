import Foundation

/// Settings › Playback › Subtitles, Subtitle Translation, Subtitle Language, Audio Language and Audio Format:
/// this device's overrides of the profile's track preferences (nil follows the server), as
/// Auto-play Trailers overrides its setting. With every override at Default the player uses
/// the server's `trackSelection` as it is; otherwise the tracks are picked on this device by
/// `ClientTrackSelector`, and online subtitles use the effective values.
@MainActor
final class TrackSettingsStore: ObservableObject {
    static let shared = TrackSettingsStore()

    /// The profile's values (this device's admin overrides layered over the profile's), shown
    /// as "Default (…)"; nil members until read.
    struct ServerValues {
        var subtitleMode: String?
        var subtitleLanguage: String?
        var audioLanguage: String?
        var allowedLanguages: [String] = []
        var translationEnabled: Bool?
    }

    /// `off`, `forced-only` or `on`.
    @Published var subtitleMode: String? { didSet { store(subtitleMode, Keys.mode) } }
    @Published var translation: Bool? { didSet { store(translation, Keys.translation) } }
    /// ISO 639-2 (`SubtitleSearchModel.Language.settingCode`).
    @Published var subtitleLanguage: String? { didSet { store(subtitleLanguage, Keys.subtitleLanguage) } }
    @Published var audioLanguage: String? { didSet { store(audioLanguage, Keys.audioLanguage) } }
    /// Audio Format: Lossless picks TrueHD (then DTS, FLAC, PCM) over the server's E-AC-3-first
    /// order. The profile has no such setting, so this is the device's alone (off = the server's).
    @Published var losslessAudio: Bool { didSet { defaults.set(losslessAudio, forKey: Keys.losslessAudio) } }

    @Published private(set) var server = ServerValues()

    private let defaults = UserDefaults.standard
    private enum Keys {
        static let mode = "strmrtv.subtitleMode"
        static let translation = "strmrtv.subtitleTranslation"
        static let subtitleLanguage = "strmrtv.subtitleLanguage"
        static let audioLanguage = "strmrtv.audioLanguage"
        static let losslessAudio = "strmrtv.losslessAudio"
    }

    private init() {
        subtitleMode = defaults.string(forKey: Keys.mode)
        translation = defaults.object(forKey: Keys.translation) as? Bool
        subtitleLanguage = defaults.string(forKey: Keys.subtitleLanguage)
        audioLanguage = defaults.string(forKey: Keys.audioLanguage)
        losslessAudio = defaults.bool(forKey: Keys.losslessAudio)
    }

    /// Any track override (translation aside, which only online subtitles read).
    var overridesTracks: Bool { subtitleMode != nil || subtitleLanguage != nil || audioLanguage != nil || losslessAudio }

    private var loaded: (profile: String, at: Date)?

    func refresh() async {
        let profile = APIClient.shared.profileID
        server = await APIClient.shared.trackServerValues()
        loaded = (profile, Date())
    }

    /// Before playback with an override: the profile's values (re-read after a profile switch
    /// or five minutes), which fill in whatever the server's track selection doesn't carry.
    func loadIfNeeded() async {
        guard overridesTracks || translation != nil else { return }
        if let loaded, loaded.profile == APIClient.shared.profileID, Date().timeIntervalSince(loaded.at) < 300 { return }
        await refresh()
    }

    /// The profile's values whether or not anything is overridden (the source list's track
    /// defaults), re-read after a profile switch or five minutes.
    func loadProfileValues() async {
        if let loaded, loaded.profile == APIClient.shared.profileID, Date().timeIntervalSince(loaded.at) < 300 { return }
        await refresh()
    }

    /// The server's translation switch with this device's override. The server's is an admin
    /// switch (its translate endpoint refuses when off), so the device can only turn it off.
    func translationEnabled(server: Bool) -> Bool { server && (translation ?? true) }

    /// Canonical mode, as the server's `NormalizeSubtitleMode`.
    static func normalizeMode(_ mode: String?) -> String? {
        guard let raw = mode?.trimmingCharacters(in: CharacterSet(charactersIn: " '\"")) else { return nil }
        switch raw {
        case "auto": return "forced-only"
        case "always": return "on"
        case "": return "off"
        default: return raw
        }
    }

    private func store<T>(_ value: T?, _ key: String) {
        if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
    }
}

extension APIClient {
    func trackServerValues() async -> TrackSettingsStore.ServerValues {
        struct Playback: Decodable {
            let preferredSubtitleMode: String?
            let preferredSubtitleLanguage: String?
            let preferredAudioLanguage: String?
            let allowedTrackLanguages: [String]?
        }
        struct UserSettings: Decodable { let playback: Playback? }
        async let user: UserSettings? = try? await send("GET", "\(profilePath)/settings", promptOnLock: false, timeout: 10)
        async let device: Playback? = try? await send("GET", "/api/clients/\(Self.segment(Config.clientID))/settings",
                                                      query: ["userId": profileID], promptOnLock: false, timeout: 10)
        async let server = subtitleServerSettings()
        let (u, d, s) = await (user?.playback, device, server)
        func pick(_ device: String?, _ user: String?) -> String? {
            [device, user].lazy.compactMap { $0 }.first { !$0.isEmpty }
        }
        return TrackSettingsStore.ServerValues(
            subtitleMode: TrackSettingsStore.normalizeMode(pick(d?.preferredSubtitleMode, u?.preferredSubtitleMode)),
            subtitleLanguage: pick(d?.preferredSubtitleLanguage, u?.preferredSubtitleLanguage),
            audioLanguage: pick(d?.preferredAudioLanguage, u?.preferredAudioLanguage),
            allowedLanguages: d?.allowedTrackLanguages ?? u?.allowedTrackLanguages ?? [],
            translationEnabled: s?.translationEnabled)
    }
}
