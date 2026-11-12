import Foundation

// MARK: - Auth / profiles

/// `POST /api/auth/login` and `POST /api/auth/refresh` (refresh rotates the token).
struct LoginResponse: Decodable {
    let token: String
    let expiresAt: String?
    let accountId: String
    let username: String
    let isMaster: Bool?
}

struct Profile: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let color: String?
    let iconUrl: String?
    let hasIcon: Bool?
    let hasPin: Bool?
    let pinLength: Int?
    let isKidsProfile: Bool?
    /// Kids profiles: "content_list" limits Home to `kidsAllowedLists` (MDBList URLs);
    /// "rating" (or none) filters by rating server-side.
    let kidsMode: String?
    let kidsAllowedLists: [String]?

    var requiresPin: Bool { hasPin == true }
    var isKidsCurated: Bool { isKidsProfile == true && kidsMode == "content_list" }
}

/// `GET /api/version` (public).
struct ServerVersion: Decodable {
    let version: String
    let buildId: String?
}

/// `GET /api/branding` (public).
struct PublicBrandingResponse: Decodable {
    let branding: PublicBranding?
}

/// Branding images uploaded in the admin UI; paths are server-relative or absolute URLs.
struct PublicBranding: Decodable, Equatable {
    let loadingLogoUrl: String?
    let homeMobileLogoUrl: String?
    let homeTvImageUrl: String?

    /// The wide logo the Expo app's sign-in shows (loading logo, else the mobile logo).
    var logoPath: String? { Self.first(loadingLogoUrl, homeMobileLogoUrl) }

    /// The profile picker's image, as in the Expo app: the TV home image on TV
    /// (else the mobile logo), the mobile logo on phones and tablets (else the TV image).
    func profilePickerPath(tv: Bool) -> String? {
        tv ? Self.first(homeTvImageUrl, homeMobileLogoUrl) : Self.first(homeMobileLogoUrl, homeTvImageUrl)
    }

    /// Resolves a branding path against the server. Uploads are stored as
    /// `/branding/images/<slot>?v=…`, which the server serves under `/api`.
    static func resolve(_ path: String?, server: URL) -> URL? {
        guard let path = path?.trimmingCharacters(in: .whitespaces), !path.isEmpty else { return nil }
        if let url = URL(string: path), let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" {
            return url
        }
        var base = server.absoluteString
        while base.hasSuffix("/") { base.removeLast() }
        let relative = path.hasPrefix("/") ? path : "/" + path
        return URL(string: base + (relative.hasPrefix("/api/") ? relative : "/api" + relative))
    }

    private static func first(_ paths: String?...) -> String? {
        paths.compactMap { $0?.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty }
    }
}

// MARK: - Shared

struct ImageRef: Decodable, Hashable {
    let url: String
}

/// A dated release window (theatrical / digital / physical).
struct Release: Decodable, Hashable {
    let date: String?
}

/// Server-computed resume decision (seconds; `percent` is 0–100). Offer resume only when
/// `eligible`; a Trakt import may carry only `percent` (position and duration 0).
struct ResumeState: Decodable, Hashable {
    let position: Double
    let duration: Double
    let percent: Double
    let eligible: Bool

    /// Where playback should start, or nil when resume isn't on offer.
    var startPoint: StartPoint? {
        guard eligible else { return nil }
        if position > 0 { return .seconds(position) }
        if percent > 0 { return .percent(percent) }
        return nil
    }

    /// 0–1, for progress bars.
    var fraction: Double { min(max(percent / 100, 0), 1) }
}

/// A resume point: an exact position, or a percentage to apply once the duration is known.
enum StartPoint: Hashable {
    case seconds(Double)
    case percent(Double)

    var label: String {
        switch self {
        case let .seconds(s): formatTimestamp(s)
        case let .percent(p): "\(Int(p.rounded()))%"
        }
    }
}

struct EpisodeRef: Decodable, Hashable {
    let seasonNumber: Int
    let episodeNumber: Int
    let absoluteEpisodeNumber: Int?
    let title: String?
    let overview: String?
    let runtimeMinutes: Int?
    let image: ImageRef?
    let airDate: String?
    let airDateTimeUTC: String?
    /// Canonical progress / watch item ID; use verbatim, never rebuild it.
    let itemId: String?

    var code: String { String(format: "S%02dE%02d", seasonNumber, episodeNumber) }
}

/// The one episode a card stands for (Continue Watching's next episode, a calendar
/// release), for its long press's single-episode Mark as Watched.
struct CardEpisode: Hashable {
    let seasonNumber: Int
    let episodeNumber: Int
    let name: String?
    /// The server's item ID when the card's source sent one.
    let itemId: String?

    var code: String { String(format: "S%02dE%02d", seasonNumber, episodeNumber) }

    init(seasonNumber: Int, episodeNumber: Int, name: String?, itemId: String?) {
        self.seasonNumber = seasonNumber
        self.episodeNumber = episodeNumber
        self.name = name
        self.itemId = itemId
    }

    init(_ ref: EpisodeRef) {
        self.init(seasonNumber: ref.seasonNumber, episodeNumber: ref.episodeNumber, name: ref.title, itemId: ref.itemId)
    }

    /// A calendar release's episode; nil for a movie or a release without its numbers.
    init?(_ item: CalendarItem) {
        guard !item.isMovie, let season = item.seasonNumber, let number = item.episodeNumber else { return nil }
        self.init(seasonNumber: season, episodeNumber: number, name: item.episodeTitle, itemId: nil)
    }
}

// MARK: - Continue watching

struct ContinueWatchingItem: Decodable, Identifiable, Hashable {
    let seriesId: String
    let seriesTitle: String
    let overview: String?
    let posterUrl: String?
    /// The poster with its title text when `posterUrl` is textless.
    let textPosterUrl: String?
    let backdropUrl: String?
    /// Title logo for the hero (newer servers only).
    let logoUrl: String?
    let year: Int?
    let externalIds: [String: String]?
    let nextEpisode: EpisodeRef?
    let percentWatched: Double?
    let resumePercent: Double?
    /// Resume state of the item this row plays (the movie, or `nextEpisode`).
    let resume: ResumeState?
    /// Backend release status: movies released/theatrical/upcoming, series released/unreleased.
    let status: String?
    /// The prequeue / prewarm state of the item the row plays ("ready" once resolved).
    let prequeueStatus: String?
    /// Series: released episodes and those watched, for the card's watch state and count.
    let totalEpisodeCount: Int?
    let watchedEpisodeCount: Int?

    var id: String { seriesId }
    var isMovie: Bool { seriesId.contains(":movie:") }
}

// MARK: - Lists

/// One page of `GET /api/users/{id}/display-list`; the server sorts, filters and pages.
struct DisplayListPage<Item: Decodable & Sendable>: Decodable, Sendable {
    let items: [Item]
    /// Items on this page after the server drops hidden titles.
    let total: Int
    /// The whole list's size before paging, when the server sends it.
    let sourceTotal: Int?
    /// Genre facets (`includeFacets=true`) and first letters present, on sources that
    /// filter server-side.
    var genres: [String]?
    var alphabetBuckets: [String]?

    /// How many items the list holds in all.
    var listTotal: Int { max(sourceTotal ?? total, items.count) }
}

/// A watchlist entry (`display-list?source=watchlist`). `id` is the server's canonical
/// ID; pass it back verbatim to remove the item.
struct WatchlistItem: Decodable, Identifiable, Hashable {
    let id: String
    /// movie | series
    let mediaType: String
    let name: String
    let overview: String?
    let year: Int?
    let posterUrl: String?
    /// The poster with its title text when `posterUrl` is textless.
    let textPosterUrl: String?
    let backdropUrl: String?
    /// Title logo, from the server's metadata cache (newer servers only).
    let logoUrl: String?
    let externalIds: [String: String]?
    /// none | partial | complete
    let watchState: String?
    /// Series: released episodes the profile hasn't watched (absent until the server knows).
    let unwatchedCount: Int?
    let status: String?
    let releaseDate: String?
    let availability: String?

    var isMovie: Bool { mediaType == "movie" }
}

/// A discovery row entry (`display-list?source=trending`).
struct TrendingItem: Decodable, Hashable {
    let rank: Int
    let title: Title
}

/// `POST /api/users/{id}/watchlist`. The server rejects unknown fields.
struct WatchlistUpsert: Encodable {
    let id: String
    let mediaType: String
    let name: String
    var overview: String?
    var year: Int?
    var posterUrl: String?
    var textPosterUrl: String?
    var backdropUrl: String?
    var externalIds: [String: String]?
}

// MARK: - Helpers

extension String {
    var asURL: URL? { URL(string: self) }
}

/// A title hidden from the profile (`/users/{id}/hidden-items`).
struct HiddenItem: Decodable, Identifiable, Hashable {
    let id: String
    /// movie | series
    let mediaType: String
    let name: String?
    let year: Int?
    let posterUrl: String?
    let backdropUrl: String?
    let externalIds: [String: String]?

    var isMovie: Bool { mediaType == "movie" }
}
