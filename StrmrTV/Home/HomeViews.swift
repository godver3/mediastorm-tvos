import Foundation

/// Home views: Home (`all`), Movies, Shows and the custom `page-…` pages, as the Expo app
/// has them (`utils/home-views.ts`). The definitions live in `homeShelves.views`, keyed by
/// view ID; the profile's entry replaces the server's one by ID.
enum HomeMediaFilter: String, Sendable {
    case all, movies, shows

    /// The `mediaType` the server's lists take (`homeViewMediaType`).
    var mediaType: String {
        switch self {
        case .all: "all"
        case .movies: "movie"
        case .shows: "series"
        }
    }
}

/// One `homeShelves.views` entry (`config.HomeViewSettings`).
struct HomeViewDefinition: Decodable, Sendable {
    var name: String?
    var icon: String?
    /// all | movies | shows: what the page shows, independent of its ID.
    var mediaFilter: String?
    /// The profile hides a page the server defines.
    var deleted: Bool?
    /// custom: the page has its own layout; inherit (or unset): it follows Home.
    var mode: String?
    /// The layout fields a custom page sets (shelves, item cap, top shelf…), read from the
    /// same object.
    var layout: HomeLayoutConfig

    private enum CodingKeys: String, CodingKey { case name, icon, mediaFilter, deleted, mode }

    init(name: String? = nil, icon: String? = nil, mediaFilter: String? = nil, deleted: Bool? = nil,
         mode: String? = nil, layout: HomeLayoutConfig = HomeLayoutConfig()) {
        self.name = name
        self.icon = icon
        self.mediaFilter = mediaFilter
        self.deleted = deleted
        self.mode = mode
        self.layout = layout
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        icon = try container.decodeIfPresent(String.self, forKey: .icon)
        mediaFilter = try container.decodeIfPresent(String.self, forKey: .mediaFilter)
        deleted = try container.decodeIfPresent(Bool.self, forKey: .deleted)
        mode = try container.decodeIfPresent(String.self, forKey: .mode)
        layout = try HomeLayoutConfig(from: decoder)
    }
}

typealias HomeViewDefinitions = [String: HomeViewDefinition]

/// The Expo app's `home-views.ts` helpers.
enum HomeViews {
    static let all = "all"

    static func isCustom(_ id: String) -> Bool {
        id.wholeMatch(of: /page-[a-zA-Z0-9-]{1,80}/) != nil
    }

    /// The page's name: Home, Movies, Shows, else the page's own name (`homeViewLabel`).
    static func label(_ view: String, _ views: HomeViewDefinitions?) -> String {
        switch view {
        case "all": String(localized: "Home")
        case "movies": String(localized: "Movies")
        case "shows": String(localized: "Shows")
        default: views?[view]?.name ?? String(localized: "Home page")
        }
    }

    /// The Expo app's page icons (Material Community names), as SF Symbols.
    static let icons: [String: String] = [
        "home-variant": "house", "movie-open": "film", "television-classic": "tv", "star": "star",
        "heart": "heart", "animation": "square.stack", "popcorn": "popcorn", "compass-outline": "safari",
    ]

    /// The page's icon (`homeViewIcon`), as an SF Symbol name.
    static func icon(_ view: String, _ views: HomeViewDefinitions?) -> String {
        if let icon = views?[view]?.icon, let symbol = icons[icon] { return symbol }
        return view == "movies" ? "film" : view == "shows" ? "tv" : "house"
    }

    /// The profile's entries over the server's, by ID; only a missing name, icon or media
    /// filter comes from the server's entry. Shelf lists never merge (`mergeHomeViews`).
    static func merge(_ global: HomeViewDefinitions?, _ profile: HomeViewDefinitions?) -> HomeViewDefinitions {
        var result = global ?? [:]
        for (id, override) in profile ?? [:] {
            let inherited = global?[id]
            var merged = override
            merged.name = override.name ?? inherited?.name
            merged.icon = override.icon ?? inherited?.icon
            merged.mediaFilter = override.mediaFilter ?? inherited?.mediaFilter
            result[id] = merged
        }
        return result
    }

    /// What a view shows (`homeViewFilter`): Movies and Shows by ID, a page by its media
    /// filter unless deleted, else everything.
    static func filter(_ view: String, _ views: HomeViewDefinitions?) -> HomeMediaFilter {
        if view == "movies" { return .movies }
        if view == "shows" { return .shows }
        guard let definition = views?[view], definition.deleted != true else { return .all }
        return definition.mediaFilter == "movies" ? .movies : definition.mediaFilter == "shows" ? .shows : .all
    }

    /// Every view the picker offers: All, Movies, Shows, then the pages not deleted, by name
    /// (`homeViewIds`).
    static func ids(_ views: HomeViewDefinitions?) -> [String] {
        let pages = (views ?? [:]).filter { isCustom($0.key) && $0.value.deleted != true }.map(\.key)
            .sorted { a, b in
                let order = label(a, views).localizedCompare(label(b, views))
                return order == .orderedSame ? a < b : order == .orderedAscending
            }
        return ["all", "movies", "shows"] + pages
    }

    /// A stored view ID, or All (`parseHomeView`).
    static func parse(_ value: String?) -> String {
        guard let value, value == "movies" || value == "shows" || isCustom(value) else { return all }
        return value
    }

    /// Whether an item of `mediaType` belongs on a view showing `filter` (`matchesHomeView`).
    static func matches(mediaType: String?, _ filter: HomeMediaFilter) -> Bool {
        let type = mediaType?.lowercased() ?? ""
        switch filter {
        case .all: return true
        case .movies: return ["movie", "movies", "film", "films"].contains(type)
        case .shows: return ["tv", "series", "show", "shows", "episode"].contains(type)
        }
    }

    /// Whether a shelf can show on a view (`homeViewShelfAllowed`): never the live,
    /// dashboard and Tonight rows on Movies or Shows, nor rows of the other media type.
    static func shelfAllowed(_ shelf: ShelfConfig, _ filter: HomeMediaFilter) -> Bool {
        if filter == .all { return true }
        if ["live-favorites", "dashboard", "tonight"].contains(shelf.id) { return false }
        if filter == .movies, ["trending-tv", "my-upcoming", "my-recently-aired"].contains(shelf.id) { return false }
        if filter == .shows, shelf.id == "trending-movies" { return false }
        let type = [shelf.addonCatalogType, shelf.tmdbMediaType, shelf.simklMediaType]
            .compactMap { $0 }.first { !$0.isEmpty }
            ?? shelf.id.firstMatch(of: /(?:genre-\d+|decade-\d+)-(movie|tv)$/).map { String($0.1) }
        guard let type, type != "all" else { return true }
        return matches(mediaType: type, filter)
    }
}
