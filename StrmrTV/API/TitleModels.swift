import Foundation

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
    /// none | partial | complete, for the profile that asked (Search, list rows).
    let watchState: String?
    /// Series: released episodes the profile hasn't watched (absent until the server knows).
    let unwatchedCount: Int?
    /// Multi-source ratings (IMDb, Rotten Tomatoes, …), hydrated from MDBList when enabled.
    let ratings: [Rating]?

    var isMovie: Bool { mediaType == "movie" }
}

/// One source's score: `source` is imdb, tmdb, trakt, tomatoes, audience, metacritic or
/// letterboxd; `value` is on that source's `max` scale.
struct Rating: Decodable, Hashable {
    let source: String
    let value: Double
    let max: Double
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
    /// TVDB season types the series can be shown in (empty or one = no choice), and the one
    /// these seasons use. The server applies the profile's saved choice (`series-ordering`).
    var availableOrderings: [SeriesOrdering]?
    var activeOrdering: String?
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
    /// The ordering these numbers are in (stamped by the server on every episode).
    var numbering: EpisodeNumbering?

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
    /// `off`, `on`, `forced-only` or `foreign-audio`.
    let subtitleMode: String?
}
