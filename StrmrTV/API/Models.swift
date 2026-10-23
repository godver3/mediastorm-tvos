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
    var logoPath: String? {
        [loadingLogoUrl, homeMobileLogoUrl].compactMap { $0?.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty }
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

    var id: String { seriesId }
    var isMovie: Bool { seriesId.contains(":movie:") }
}

// MARK: - Search

struct SearchResult: Decodable, Identifiable, Hashable {
    let title: Title
    /// The server's relevance; results from the three searches are merged by it.
    var score: Double?
    var id: String { title.id }
}

/// Title metadata as returned by search and the details endpoints.
struct Title: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let overview: String?
    let year: Int?
    let poster: ImageRef?
    /// The poster with its title text when the server swapped `poster` for a textless one.
    let textPoster: ImageRef?
    let backdrop: ImageRef?
    /// Alternative backdrops beyond the primary one.
    let backdrops: [ImageRef]?
    let logo: ImageRef?
    let mediaType: String
    let imdbId: String?
    let tmdbId: Int?
    let tvdbId: Int?
    let certification: String?
    let runtimeMinutes: Int?
    let genres: [String]?
    let status: String?
    let theatricalRelease: Release?
    let homeRelease: Release?
    /// `YYYY-MM-DD` the title first becomes watchable.
    let releaseDate: String?
    /// released | theatrical | coming_soon | unreleased (newer servers only).
    let availability: String?
    /// Top-billed cast (details only).
    let credits: Credits?
    /// Movies: the collection the movie belongs to (details only).
    let collection: CollectionRef?

    var isMovie: Bool { mediaType == "movie" }
}

struct Credits: Decodable, Hashable {
    let cast: [CastMember]
}

struct CastMember: Decodable, Hashable {
    /// The TMDB person ID.
    let id: Int
    let name: String
    let character: String?
    let profileUrl: String?
}

/// A movie collection ("The Matrix Collection"), as named on a movie's details.
struct CollectionRef: Decodable, Hashable {
    let id: Int
    let name: String
}

/// `GET /api/metadata/collection`: the collection's movies.
struct CollectionDetails: Decodable {
    let id: Int
    let name: String
    let movies: [Title]?
}

/// A person a cast card opens; the navigation value for `PersonPage`.
struct PersonRef: Hashable {
    let id: Int
    let name: String
    let profileURL: String?
}

/// `GET /api/metadata/person`: the person and the titles they appear in.
struct PersonDetails: Decodable {
    struct Person: Decodable {
        let id: Int
        let name: String
        let biography: String?
        let profileUrl: String?
        let knownFor: String?
    }

    let person: Person
    let filmography: [Title]?
}

// MARK: - Series details

struct SeriesDetails: Decodable {
    let title: Title
    let seasons: [Season]
}

struct Season: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let number: Int
    let episodes: [Episode]
}

struct Episode: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let overview: String?
    let seasonNumber: Int
    let episodeNumber: Int
    let absoluteEpisodeNumber: Int?
    let runtimeMinutes: Int?
    let image: ImageRef?
    let airedDate: String?
    /// Per-user fields, present on `/details-bundle` responses only.
    let itemId: String?
    let watched: Bool?
    let resume: ResumeState?

    var code: String { String(format: "S%02dE%02d", seasonNumber, episodeNumber) }
}

// MARK: - Details bundle

/// `GET /api/users/{id}/details-bundle`: details plus the per-user progress state.
struct DetailsBundle: Decodable {
    let seriesDetails: SeriesDetails?
    let movieDetails: Title?
    /// Series: the episode the page offers to play, with its `itemId`.
    let upNextEpisode: EpisodeRef?
    /// Resume state for the movie, or for `upNextEpisode`.
    let resume: ResumeState?
    /// Watchlist membership, matched server-side across ID forms (newer servers only).
    let inWatchlist: Bool?
    /// Movies: watched, matched server-side across ID forms (newer servers only).
    let watched: Bool?
    /// Titles like this one (More Like This).
    let similar: [Title]?
    /// Trailers, the server's pick first (`primaryTrailer`).
    let trailers: TrailerList?
    /// The profile's per-title track languages (nil when none is set).
    let contentPreference: ContentPreference?
}

/// A profile's audio / subtitle choice for one title, which beats its playback settings.
struct ContentPreference: Decodable, Hashable {
    let audioLanguage: String?
    let subtitleLanguage: String?
    /// `off`, `on` or `forced-only`.
    let subtitleMode: String?
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
