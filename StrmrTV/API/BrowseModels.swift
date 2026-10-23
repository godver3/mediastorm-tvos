import Foundation

/// A custom list (`GET /api/users/{id}/custom-lists`).
struct CustomList: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let itemCount: Int?

    /// The reserved "Set Aside" list: titles parked out of Continue Watching.
    var isSetAside: Bool {
        name.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare("Set Aside") == .orderedSame
    }
}

/// A list the Lists tab opens. Hashable, so it is also the grid's navigation value.
enum BrowseList: Hashable {
    case custom(id: String, name: String)
    case watchlist
    /// Opens the Continue Watching grid (its own view, not a `display-list` grid).
    case continueWatching
    /// Titles the server keeps resolved until they are removed.
    case permanentPrequeue
    /// Titles hidden from the profile (its own view, from `hidden-items`).
    case hidden
    /// Movies and shows together when the kind is nil.
    case topTen(BrowseKind?)
    case trending(BrowseKind)
    case popularOnServer
    /// The server's recommendations from the profile's watch history.
    case personalized
    /// Titles like one the profile is watching, with that title's backdrop for the tile.
    case similar(tmdbID: String, kind: BrowseKind, seed: String, backdrop: String?)
    case genre(Genre, BrowseKind)
    case decade(Int, BrowseKind)
    /// A list configured as a home shelf (MDBList, Stremio, TMDB, Trakt…), with its
    /// `display-list` query.
    case remote(id: String, name: String, query: [String: String])
    /// A streaming service's top lists; the grid switches between them (`BrowseOptions.part`).
    case service(StreamingService)
    /// A local, Plex or Jellyfin library, paged from `/api/library` (`APIClient.libraryPage`).
    case library(LibraryRef)

    /// The server's AI picks for a description (`display-list?source=custom-ai&q=`), cached
    /// server-side per description, so paging and sorting don't ask again.
    static func askAI(_ prompt: String) -> BrowseList {
        let name = String(localized: "Ask AI: \(prompt)")
        return .remote(id: "custom-ai", name: name, query: ["source": "custom-ai", "q": prompt, "name": name])
    }

    var title: String {
        switch self {
        case let .custom(_, name): name
        case .watchlist: String(localized: "Watchlist")
        case .continueWatching: String(localized: "Continue Watching")
        case .permanentPrequeue: String(localized: "Permanent Prequeue")
        case .hidden: String(localized: "Hidden")
        case .topTen(nil): String(localized: "Top 10 Today")
        case let .topTen(kind?): kind == .movies ? String(localized: "Top 10 Movies") : String(localized: "Top 10 Shows")
        case let .trending(kind): kind == .movies ? String(localized: "Trending Movies") : String(localized: "Trending Shows")
        case .popularOnServer: String(localized: "Popular on This Server")
        case .personalized: String(localized: "Recommended for You")
        case let .similar(_, _, seed, _): String(localized: "Because You Watched \(seed)")
        case let .genre(genre, kind): "\(genre.name) \(kind.noun)"
        case let .decade(decade, kind): "\(String(decade))s \(kind.noun)"
        case let .remote(_, name, _): name
        case let .service(service): service.name
        case let .library(library): library.name
        }
    }

    /// Lists the grid switches between (a streaming service's movies and shows).
    var parts: [String] {
        guard case let .service(service) = self else { return [] }
        return service.lists.enumerated().map { $1.title ?? String(localized: "List \($0 + 1)") }
    }

    /// Remote lists the server can page without reading the whole source first
    /// (`progressiveShelfSource` in the backend).
    var loadsProgressively: Bool {
        switch self {
        case let .remote(_, _, query):
            ["mdblist", "trakt-list", "stremio", "simkl-list", "letterboxd-list", "publicmetadb-list", "tmdb-list"]
                .contains(query["source"]?.lowercased() ?? "")
        case .service: true
        default: false
        }
    }

    /// How the source's `display-list` items are shaped.
    enum ItemShape { case item, ranked, title }

    var itemShape: ItemShape {
        switch self {
        case .custom, .watchlist, .permanentPrequeue, .continueWatching, .hidden: .item
        case .similar: .title
        case .topTen, .trending, .popularOnServer, .personalized, .genre, .decade, .remote, .service: .ranked
        case .library: .title  // not read: libraries page through `libraryPage`
        }
    }

    /// The sorts the server applies for this source. Custom lists are sorted and filtered
    /// by `display-list` itself; genre and decade lists pass name / year / rating on to
    /// TMDB discover (default: popularity); the charts come in their own order.
    var sorts: [BrowseSort] {
        switch self {
        case .custom, .watchlist, .permanentPrequeue: [.default, .added, .name, .year, .duration, .rating]
        case .genre, .decade, .remote, .service, .trending: [.default, .name, .year, .rating]
        case .topTen, .popularOnServer, .personalized, .similar, .continueWatching, .hidden: []
        case .library: [.default, .added, .name, .year]
        }
    }

    /// The A–Z index under a Name sort: the profile's own lists and libraries.
    var indexesLetters: Bool {
        if case .library = self { return true }
        return filters
    }

    /// Movies / Shows, watch status, genre facets and the A–Z index (the profile's own lists).
    var filters: Bool {
        switch self {
        case .custom, .watchlist, .permanentPrequeue: true
        default: false
        }
    }

    /// A random pick only makes sense past a handful of titles.
    var offersRandom: Bool {
        switch self {
        case .topTen, .continueWatching, .hidden: false
        default: true
        }
    }

    /// `display-list` query parameters, without paging.
    var query: [String: String] {
        switch self {
        case let .custom(id, _): ["source": "custom-list", "listId": id]
        case .watchlist: ["source": "watchlist"]
        case .continueWatching: ["source": "continue-watching"]
        case .hidden: [:]
        case .permanentPrequeue: ["source": "permanent-prequeue"]
        case let .topTen(kind): ["source": "top-ten"].merging(kind.map { ["mediaType": $0.mediaType] } ?? [:]) { a, _ in a }
        case let .trending(kind): ["source": "trending", "mediaType": kind.mediaType]
        case .popularOnServer: ["source": "popular-on-server"]
        case .personalized: ["source": "personalized"]
        case let .similar(tmdbID, kind, _, _): ["source": "similar", "tmdbId": tmdbID, "mediaType": kind.mediaType]
        case let .genre(genre, kind): ["source": "genre", "genreId": String(genre.id), "mediaType": kind.mediaType]
        case let .decade(decade, kind): ["source": "decade", "decade": String(decade), "mediaType": kind.mediaType]
        case let .remote(_, _, query): query
        case let .service(service): ["source": "mdblist", "name": service.name, "url": service.lists.first?.url ?? ""]
        case .library: [:]
        }
    }
}

enum BrowseKind: String, CaseIterable, Identifiable, Hashable {
    case movies, shows
    var id: Self { self }

    var mediaType: String { self == .movies ? "movie" : "series" }
    var noun: String { self == .movies ? String(localized: "Movies") : String(localized: "Shows") }

    /// TMDB's genres for this kind; movie and TV genre ids differ.
    var genres: [Genre] { self == .movies ? Genre.movie : Genre.tv }
}

/// A TMDB genre. The server passes the id straight to TMDB discover, so the ids are
/// TMDB's own (stable, and the same in every language).
struct Genre: Hashable, Identifiable {
    let id: Int
    let name: String

    static let movie: [Genre] = [
        .init(id: 28, name: String(localized: "Action")),
        .init(id: 12, name: String(localized: "Adventure")),
        .init(id: 16, name: String(localized: "Animation")),
        .init(id: 35, name: String(localized: "Comedy")),
        .init(id: 80, name: String(localized: "Crime")),
        .init(id: 99, name: String(localized: "Documentary")),
        .init(id: 18, name: String(localized: "Drama")),
        .init(id: 10751, name: String(localized: "Family")),
        .init(id: 14, name: String(localized: "Fantasy")),
        .init(id: 36, name: String(localized: "History")),
        .init(id: 27, name: String(localized: "Horror")),
        .init(id: 10402, name: String(localized: "Music")),
        .init(id: 9648, name: String(localized: "Mystery")),
        .init(id: 10749, name: String(localized: "Romance")),
        .init(id: 878, name: String(localized: "Science Fiction")),
        .init(id: 53, name: String(localized: "Thriller")),
        .init(id: 10752, name: String(localized: "War")),
        .init(id: 37, name: String(localized: "Western")),
    ]

    static let tv: [Genre] = [
        .init(id: 10759, name: String(localized: "Action & Adventure")),
        .init(id: 16, name: String(localized: "Animation")),
        .init(id: 35, name: String(localized: "Comedy")),
        .init(id: 80, name: String(localized: "Crime")),
        .init(id: 99, name: String(localized: "Documentary")),
        .init(id: 18, name: String(localized: "Drama")),
        .init(id: 10751, name: String(localized: "Family")),
        .init(id: 10762, name: String(localized: "Kids")),
        .init(id: 9648, name: String(localized: "Mystery")),
        .init(id: 10764, name: String(localized: "Reality")),
        .init(id: 10765, name: String(localized: "Sci-Fi & Fantasy")),
        .init(id: 10768, name: String(localized: "War & Politics")),
        .init(id: 37, name: String(localized: "Western")),
    ]

}

extension BrowseKind {
    /// Decades TMDB discover has enough titles for, newest first.
    var decades: [Int] { Array(stride(from: 2020, through: self == .movies ? 1930 : 1950, by: -10)) }
}

/// A list entry: discovery sources send titles, custom lists send list items.
enum BrowseEntry: Identifiable, Hashable {
    case title(Title)
    case item(WatchlistItem)
    case library(LibraryEntry)

    var id: String {
        switch self {
        case let .title(title): title.id
        case let .item(item): item.id
        case let .library(entry): entry.id
        }
    }

    var posterURL: String? {
        switch self {
        case let .title(title): title.textPoster?.url ?? title.poster?.url
        case let .item(item): item.textPosterUrl ?? item.posterUrl
        case let .library(entry): entry.group.posterURL
        }
    }

    var backdropURL: String? {
        switch self {
        case let .title(title): title.backdrop?.url
        case let .item(item): item.backdropUrl
        case let .library(entry): entry.group.backdropURL
        }
    }
}

/// How much of a progressive list (`BrowseList.loadsProgressively`) the server prepares
/// before answering, as the Expo home asks for it. Without a phase the server reads the
/// whole source (up to 500 titles, every page of a Stremio catalog) and fills in every
/// title's metadata before returning the first page.
enum ShelfPhase: String, Sendable {
    /// The first cards fast: only enough of the source to fill the page, artwork from
    /// cache or the source itself, the total possibly an estimate.
    case cards
    /// The same page with full metadata and the exact total.
    case complete

    var query: [String: String] {
        ["shelfPhase": rawValue, "lite": "true", "deferArtwork": String(self == .cards),
         "artworkLimit": self == .cards ? "20" : "50"]
    }
}

struct BrowsePage {
    let entries: [BrowseEntry]
    /// The whole list's size after filtering.
    let total: Int
    /// Genre facets of the filtered list (when the source's items carry genres).
    var genres: [String] = []
    /// First letters present in the filtered list, for the A–Z index.
    var letters: [String] = []
}

enum BrowseSort: String, Hashable, CaseIterable {
    case `default`, added, name, year, duration, rating

    var label: String {
        switch self {
        case .default: String(localized: "Default")
        case .added: String(localized: "Date Added")
        case .name: String(localized: "Name")
        case .year: String(localized: "Year")
        case .duration: String(localized: "Duration")
        case .rating: String(localized: "Rating")
        }
    }

    /// Names read A to Z; dates, lengths and ratings start at the top.
    var ascendingByDefault: Bool { self == .name }
}

/// Watch-status filter, in the server's vocabulary (it also accepts these aliases).
enum WatchFilter: String, Hashable, CaseIterable {
    case all, unwatched, inProgress = "in_progress", watched

    var label: String {
        switch self {
        case .all: String(localized: "Any Status")
        case .unwatched: String(localized: "Unwatched")
        case .inProgress: String(localized: "In Progress")
        case .watched: String(localized: "Watched")
        }
    }
}

/// Rating sources the server can sort custom lists by (MDBList ratings on each item).
enum RatingSource: String, Hashable, CaseIterable {
    case imdb, tmdb, trakt, letterboxd, tomatoes, audience, metacritic

    var label: String {
        switch self {
        case .imdb: "IMDb"
        case .tmdb: "TMDB"
        case .trakt: "Trakt"
        case .letterboxd: "Letterboxd"
        case .tomatoes: String(localized: "Rotten Tomatoes")
        case .audience: String(localized: "RT Audience")
        case .metacritic: "Metacritic"
        }
    }
}

/// The browse grid's sort and filters. Changing any of them reloads the list.
struct BrowseOptions: Hashable {
    var sort: BrowseSort = .default
    var ascending = false
    var ratingSource: RatingSource = .imdb
    var kind: BrowseKind?
    var watch: WatchFilter = .all
    var genres: Set<String> = []
    var letter: String?
    /// Which of the list's `parts` is shown.
    var part = 0

    var isFiltered: Bool { kind != nil || watch != .all || !genres.isEmpty }

    /// Picks a sort, or flips the direction when it is already the current one.
    mutating func choose(_ sort: BrowseSort) {
        if self.sort == sort, sort != .default {
            ascending.toggle()
        } else {
            self.sort = sort
            ascending = sort.ascendingByDefault
        }
        if sort != .name { letter = nil }
    }

    func query(for list: BrowseList) -> [String: String] {
        var q: [String: String] = [:]
        if case let .service(service) = list, service.lists.indices.contains(part) {
            q["url"] = service.lists[part].url
        }
        if sort != .default, list.sorts.contains(sort) {
            q["sortBy"] = sort.rawValue
            q["sortDirection"] = ascending ? "asc" : "desc"
            if sort == .rating, list.filters { q["ratingSource"] = ratingSource.rawValue }
        }
        guard list.filters else { return q }
        q["includeFacets"] = "true"
        if let kind { q["filterMediaType"] = kind.mediaType }
        if watch != .all { q["watchStatus"] = watch.rawValue }
        if !genres.isEmpty { q["genres"] = genres.sorted().joined(separator: ",") }
        if let letter { q["alphabet"] = letter }
        return q
    }
}
