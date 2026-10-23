import Foundation

/// The lists a server admin or the profile configured as home shelves (MDBList, Stremio,
/// TMDB, Trakt, PublicMetaDB, Simkl, Letterboxd), the streaming services and collection
/// hubs. The Lists tab offers all of them, enabled on Home or not.
extension APIClient {
    /// `homeShelves.shelves` from the profile's settings (server defaults filled in).
    func shelfConfigs() async throws -> [ShelfConfig] {
        struct Home: Decodable { let shelves: [ShelfConfig]? }
        struct Settings: Decodable { let homeShelves: Home? }
        let settings: Settings = try await send("GET", "\(profilePath)/settings")
        return settings.homeShelves?.shelves ?? []
    }
}

struct ShelfConfig: Decodable, Hashable {
    let id: String
    let name: String?
    var enabled: Bool?
    var order: Int?
    let type: String?
    /// Cards the row shows; 0 / nil for the profile's `itemCap`.
    let limit: Int?
    let activityWindowDays: Int?
    let minimumProfiles: Int?
    let maxItemsPerProfile: Int?
    /// Which calendar sources a recently-aired shelf takes (watchlist only when unset).
    let calendarSources: CalendarSources?
    let listUrl: String?
    let addonManifestUrl: String?
    let addonCatalogType: String?
    let addonCatalogId: String?
    let tmdbSourceType: String?
    let tmdbSourceId: String?
    let tmdbMediaType: String?
    let tmdbDiscoverQuery: String?
    var sort: String?
    let traktAccountId: String?
    let traktListType: String?
    let traktListId: String?
    let publicMetaDBAccountId: String?
    let publicMetaDBListId: String?
    let simklAccountId: String?
    let simklListType: String?
    let simklMediaType: String?
    let letterboxdListId: String?
    let letterboxdListUrl: String?
    let hideUnreleased: Bool?
    let streamingServices: [StreamingService]?
    let collectionItems: [CollectionLink]?

    struct CalendarSources: Decodable, Hashable {
        let watchlist: Bool?
        let history: Bool?
        let trending: Bool?
        let topTrending: Bool?
        let mdblists: Bool?
    }

    var title: String { name?.isEmpty == false ? name! : id }

    /// The `display-list` query for a remote list shelf, as the server builds it for Home
    /// (`startupDisplayListQueryForShelf`), without paging. Nil for other shelves.
    var remoteQuery: [String: String]? {
        func value(_ s: String?) -> String? {
            let t = s?.trimmingCharacters(in: .whitespaces) ?? ""
            return t.isEmpty ? nil : t
        }
        var q: [String: String] = ["name": title]
        if hideUnreleased == true { q["hideUnreleased"] = "true" }
        switch type?.lowercased() {
        case "mdblist":
            guard let url = value(listUrl) else { return nil }
            q["source"] = "mdblist"
            q["url"] = url
        case "stremio":
            guard let manifest = value(addonManifestUrl), let type = value(addonCatalogType),
                  let catalog = value(addonCatalogId) else { return nil }
            q["source"] = "stremio"
            q["manifestUrl"] = manifest
            q["catalogType"] = type
            q["catalogId"] = catalog
        case "tmdb":
            guard let sourceType = value(tmdbSourceType) else { return nil }
            q["source"] = "tmdb-list"
            q["sourceType"] = sourceType
            q["sourceId"] = value(tmdbSourceId) ?? ""
            q["mediaType"] = value(tmdbMediaType) ?? ""
            q["sort"] = value(sort) ?? ""
            q["discoverQuery"] = value(tmdbDiscoverQuery) ?? ""
        case "trakt":
            guard let account = value(traktAccountId), let listType = value(traktListType) else { return nil }
            q["source"] = "trakt-list"
            q["accountId"] = account
            q["listType"] = listType
            if let list = value(traktListId) { q["listId"] = list }
        case "publicmetadb":
            guard let account = value(publicMetaDBAccountId), let list = value(publicMetaDBListId) else { return nil }
            q["source"] = "publicmetadb-list"
            q["accountId"] = account
            q["listId"] = list
        case "simkl":
            guard let account = value(simklAccountId), let media = value(simklMediaType) else { return nil }
            q["source"] = "simkl-list"
            q["accountId"] = account
            q["mediaType"] = media
            if let listType = value(simklListType) { q["listType"] = listType }
        case "letterboxd":
            let id = value(letterboxdListId), url = value(letterboxdListUrl)
            guard id != nil || url != nil else { return nil }
            q["source"] = "letterboxd-list"
            if let id { q["listId"] = id }
            if let url { q["listUrl"] = url }
        default:
            return nil
        }
        return q
    }

    /// The list a shelf opens in the Lists tab: a remote list, or one of the built-in
    /// sources the tab knows. Nil for shelves it can't open (calendar, libraries…).
    var browseList: BrowseList? {
        if let remoteQuery { return .remote(id: id, name: title, query: remoteQuery) }
        switch id {
        case "watchlist": return .watchlist
        case "continue-watching": return .continueWatching
        case "trending-movies": return .trending(.movies)
        case "trending-tv": return .trending(.shows)
        case "popular-on-server": return .popularOnServer
        case "permanent-prequeue": return .permanentPrequeue
        default: break
        }
        // genre-{id}-{movie|tv} / decade-{year}-{movie|tv}
        let parts = id.split(separator: "-")
        if parts.count == 3, let number = Int(parts[1]) {
            let kind: BrowseKind = parts[2] == "movie" ? .movies : .shows
            if parts[0] == "genre", let genre = kind.genres.first(where: { $0.id == number }) { return .genre(genre, kind) }
            if parts[0] == "decade" { return .decade(number, kind) }
        }
        return nil
    }
}

/// A card of a collection hub shelf: opens another shelf's list.
struct CollectionLink: Decodable, Hashable {
    let id: String
    let name: String?
    let enabled: Bool?
    let order: Int?
    let sourceShelfId: String?
    let logoUrl: String?
    let heroArtUrl: String?
}

/// A streaming service card: its top lists (usually movies and shows) from MDBList.
struct StreamingService: Decodable, Hashable {
    let id: String
    let name: String
    var enabled: Bool?
    var order: Int?
    let logoUrl: String?
    let lists: [ServiceList]

    struct ServiceList: Decodable, Hashable {
        var key: String?
        var title: String?
        let url: String
    }

    /// The configured services, or the defaults when the server has none. Disabled
    /// services, services without lists, and repeated list URLs are dropped; retired
    /// URLs are swapped for their replacements.
    static func resolved(_ configured: [StreamingService]?) -> [StreamingService] {
        guard let configured, !configured.isEmpty else { return defaults }
        return configured.enumerated()
            .filter { $0.element.enabled != false && !$0.element.name.isEmpty && $0.element.logoUrl?.isEmpty == false }
            .map { index, service in
                var seen = Set<String>()
                let lists = service.lists.compactMap { list -> ServiceList? in
                    let url = retired(list.url)
                    guard !url.isEmpty, seen.insert(url).inserted else { return nil }
                    return ServiceList(key: list.key, title: list.title, url: url)
                }
                return StreamingService(id: service.id, name: service.name, enabled: true,
                                        order: service.order ?? index, logoUrl: service.logoUrl, lists: lists)
            }
            .filter { !$0.lists.isEmpty }
            .sorted { ($0.order ?? 0) < ($1.order ?? 0) }
    }

    private static func retired(_ url: String) -> String {
        let normalized = url.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "/+$", with: "", options: .regularExpression)
            .replacingOccurrences(of: "/json$", with: "", options: .regularExpression)
        return [
            "https://mdblist.com/lists/snoak/top-hulu-movies": "https://mdblist.com/lists/azodath/top-hulu-movies/json",
            "https://mdblist.com/lists/snoak/top-tv-shows-hulu": "https://mdblist.com/lists/azodath/top-hulu-shows/json",
        ][normalized] ?? url.trimmingCharacters(in: .whitespaces)
    }

    /// The Expo app's built-in services (`constants/streamingServices.ts`).
    static let defaults: [StreamingService] = [
        .init(id: "netflix", name: "Netflix", logoUrl: "https://image.tmdb.org/t/p/original/wwemzKWzjKYJFfCeiB57q3r4Bcm.png",
              movies: "https://mdblist.com/lists/snoak/netflix-top-10-movies/json",
              shows: "https://mdblist.com/lists/snoak/netflix-top-10-shows/json"),
        .init(id: "disney", name: "Disney+", logoUrl: "https://image.tmdb.org/t/p/original/1edZOYAfoyZyZ3rklNSiUpXX30Q.png",
              movies: "https://mdblist.com/lists/snoak/disney-plus-top-10-movies/json",
              shows: "https://mdblist.com/lists/snoak/disney-plus-top-10-tv-shows/json"),
        .init(id: "amazon", name: "Amazon Prime", logoUrl: "https://image.tmdb.org/t/p/original/w7HfLNm9CWwRmAMU58udl2L7We7.png",
              movies: "https://mdblist.com/lists/snoak/amazon-prime-top-10-shows/json",
              shows: "https://mdblist.com/lists/snoak/amazon-prime-top-10-tv-shows/json"),
        .init(id: "appletv", name: "Apple TV+",
              logoUrl: "https://image.tmdb.org/t/p/w780_filter(negate,000,fff)/bngHRFi794mnMq34gfVcm9nDxN1.png",
              movies: "https://mdblist.com/lists/snoak/apple-tv-top-10-movies/json",
              shows: "https://mdblist.com/lists/snoak/apple-tv-top-10-tv-shows/json"),
        .init(id: "paramount", name: "Paramount+", logoUrl: "https://image.tmdb.org/t/p/original/fi83B1oztoS47xxcemFdPMhIzK.png",
              movies: "https://mdblist.com/lists/snoak/paramount-plus-top-10-movies/json",
              shows: "https://mdblist.com/lists/snoak/paramount-plus-top-10-tv-shows/json"),
        .init(id: "hbomax", name: "HBO Max",
              logoUrl: "https://cdn.prod.website-files.com/6911e6b4bcc8af690d496a26/6911e6b4bcc8af690d496fed_nav-hbo-max.png",
              movies: "https://mdblist.com/lists/snoak/hbo-top-10-movies-2/json",
              shows: "https://mdblist.com/lists/snoak/hbo-top-10-tv-shows/json"),
        .init(id: "hulu", name: "Hulu", logoUrl: "https://image.tmdb.org/t/p/original/pqUTCleNUiTLAVlelGxUgWn1ELh.png",
              movies: "https://mdblist.com/lists/azodath/top-hulu-movies/json",
              shows: "https://mdblist.com/lists/azodath/top-hulu-shows/json"),
        .init(id: "crunchyroll", name: "Crunchyroll", logoUrl: "https://image.tmdb.org/t/p/original/qqyXcZlJQKlRmAD1TCKV7mGLQlt.png",
              movies: "https://mdblist.com/lists/snoak/trending-anime-movies/json",
              shows: "https://mdblist.com/lists/snoak/trending-anime-shows/json"),
    ]
}

private extension StreamingService {
    init(id: String, name: String, logoUrl: String, movies: String, shows: String) {
        self.init(id: id, name: name, logoUrl: logoUrl, lists: [
            ServiceList(key: "\(id)-movies", title: "Movies", url: movies),
            ServiceList(key: "\(id)-shows", title: "Shows", url: shows),
        ])
    }
}
