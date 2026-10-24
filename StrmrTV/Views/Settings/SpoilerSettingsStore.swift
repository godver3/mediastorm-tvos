import Foundation

/// Settings › Spoilers: this device's overrides of the profile's spoiler settings
/// (`APIClient.EpisodePrivacy`; nil follows the server), as Auto-play Trailers overrides its
/// setting. Details pages hide what these say through `hides(_:…)`.
@MainActor
final class SpoilerSettingsStore: ObservableObject {
    static let shared = SpoilerSettingsStore()

    @Published var blurThumbnails: Bool? { didSet { store(blurThumbnails, Keys.thumbnails) } }
    @Published var thumbnailsIncludeNext: Bool? { didSet { store(thumbnailsIncludeNext, Keys.thumbnailsNext) } }
    @Published var blurOverviews: Bool? { didSet { store(blurOverviews, Keys.overviews) } }
    @Published var overviewsIncludeNext: Bool? { didSet { store(overviewsIncludeNext, Keys.overviewsNext) } }

    /// The profile's values, shown as "Default (…)"; nil members until read.
    @Published private(set) var server = APIClient.EpisodePrivacy()

    private let defaults = UserDefaults.standard
    private enum Keys {
        static let thumbnails = "strmrtv.blurUnwatchedThumbnails"
        static let thumbnailsNext = "strmrtv.blurUnwatchedThumbnailsIncludeNext"
        static let overviews = "strmrtv.blurUnwatchedOverviews"
        static let overviewsNext = "strmrtv.blurUnwatchedOverviewsIncludeNext"
    }

    private init() {
        blurThumbnails = defaults.object(forKey: Keys.thumbnails) as? Bool
        thumbnailsIncludeNext = defaults.object(forKey: Keys.thumbnailsNext) as? Bool
        blurOverviews = defaults.object(forKey: Keys.overviews) as? Bool
        overviewsIncludeNext = defaults.object(forKey: Keys.overviewsNext) as? Bool
    }

    func refresh() async {
        server = await APIClient.shared.episodePrivacy()
    }

    enum Part { case thumbnail, overview }

    /// The Expo `shouldBlurEpisodeContent`: an unwatched episode's part is hidden when its
    /// setting is on and the episode comes after `current` (the up-next episode, else the
    /// first), or is `current` itself with "Include Next Episode" on. Specials always count
    /// as after it.
    func hides(_ part: Part, of episode: Episode, current: Episode?, watched: Bool) -> Bool {
        let (enabled, includeNext) = switch part {
        case .thumbnail: (blurThumbnails ?? server.blurThumbnails ?? false,
                          thumbnailsIncludeNext ?? server.thumbnailsIncludeNext ?? false)
        case .overview: (blurOverviews ?? server.blurOverviews ?? false,
                         overviewsIncludeNext ?? server.overviewsIncludeNext ?? false)
        }
        guard enabled, !watched else { return false }
        return includeNext || !Self.isAtOrBefore(episode, current)
    }

    private static func isAtOrBefore(_ episode: Episode, _ current: Episode?) -> Bool {
        guard let current, episode.seasonNumber > 0 else { return false }
        if episode.seasonNumber == current.seasonNumber, episode.episodeNumber == current.episodeNumber { return true }
        guard current.seasonNumber > 0 else { return false }
        return (episode.seasonNumber, episode.episodeNumber) < (current.seasonNumber, current.episodeNumber)
    }

    private func store(_ value: Bool?, _ key: String) {
        if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
    }
}
