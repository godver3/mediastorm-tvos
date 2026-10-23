import Foundation

/// What Home is built from: the profile's `homeShelves` config (rows, order, caps), the
/// manifest that says when it went stale, and the calendar and dashboard feeds behind
/// the rows that aren't `display-list` lists.
extension APIClient {
    /// The profile's Home as `view` (a Home view ID; `all` for Home itself) lays it out:
    /// the view's resolved layout (`HomeViews.resolve`) and the profile's view definitions.
    func homeSettings(view: String = HomeViews.all) async throws -> HomeSettings {
        struct Display: Decodable { let hideWatched: Bool? }
        struct Settings: Decodable {
            let homeShelves: HomeShelvesConfig?
            let display: Display?
        }
        struct Metadata: Decodable {
            let aiApiKey: String?
            let geminiApiKey: String?
        }
        struct ServerHome: Decodable { let tvTopShelfMode: String?; let tvTopShelfSourceId: String? }
        struct ServerSettings: Decodable { let metadata: Metadata?; let homeShelves: ServerHome? }
        /// This device's overrides (`/api/clients/{id}/settings`), set in the admin UI.
        struct Device: Decodable { let homeShelfFocusModel: String? }

        // The server's own settings only say whether an AI key is set (masked); a
        // failure there just hides the AI-backed Watch Something card.
        async let server: ServerSettings? = try? await send("GET", "/api/settings", timeout: 10)
        async let device: Device? = try? await send("GET", "/api/clients/\(Self.segment(Config.clientID))/settings",
                                                    query: ["userId": profileID], promptOnLock: false, timeout: 10)
        let settings: Settings = try await send("GET", "\(profilePath)/settings")
        let metadata = await server?.metadata
        let serverHome = await server?.homeShelves
        let deviceFocusModel = await device?.homeShelfFocusModel
        // The profile's settings come with the server's shelves and views merged in; only
        // the top shelf falls back to the server's own.
        let global = HomeShelvesConfig(layout: HomeLayoutConfig(tvTopShelfMode: serverHome?.tvTopShelfMode,
                                                                tvTopShelfSourceId: serverHome?.tvTopShelfSourceId))
        let views = HomeViews.merge(nil, settings.homeShelves?.views)
        let view = HomeViews.ids(views).contains(view) ? view : HomeViews.all
        let home = HomeViews.resolve(global: global, profile: settings.homeShelves, view: view)
        return HomeSettings(
            shelves: (home.shelves ?? []).sorted { ($0.order ?? 0) < ($1.order ?? 0) },
            itemCap: home.itemCap.flatMap { $0 > 0 ? $0 : nil } ?? 20,
            exploreFirst: home.exploreCardPosition != "end",
            hideWatched: settings.display?.hideWatched ?? false,
            excludeUpcomingFromContinue: home.excludeUpcomingFromContinue ?? true,
            layout: ProfileHomeLayout(focusModel: deviceFocusModel ?? home.homeShelfFocusModel,
                                      disableCardExpansion: home.disableTvLandscapeCardExpansion,
                                      shelfScale: home.homeShelfScale, heroScale: home.homeHeroScale),
            hasAI: [metadata?.aiApiKey, metadata?.geminiApiKey].contains { $0?.isEmpty == false },
            topShelfMode: TopShelfMode(rawValue: home.tvTopShelfMode ?? "") ?? .standard,
            topShelfSourceID: home.tvTopShelfSourceId,
            view: view, filter: HomeViews.filter(view, views), views: views)
    }

    /// The profile's Home view definitions (server's merged in), for the menu and picker.
    func homeViews() async throws -> HomeViewDefinitions {
        struct Settings: Decodable { let homeShelves: HomeShelvesConfig? }
        let settings: Settings = try await send("GET", "\(profilePath)/settings", promptOnLock: false, timeout: 15)
        return HomeViews.merge(nil, settings.homeShelves?.views)
    }

    /// A fingerprint of everything Home shows that the server tracks (settings, shelf
    /// config, Continue Watching, watchlist, hidden titles); nil when it can't be read.
    func homeRevision() async -> String? {
        struct Manifest: Decodable { let revision: String? }
        let manifest: Manifest? = try? await send("GET", "\(profilePath)/home/manifest", promptOnLock: false, timeout: 15)
        return manifest?.revision
    }

    /// The calendar window Home's calendar rows use: two weeks ahead and the recent past.
    /// Throws `HomeCalendarPending` while the server is still building the profile's calendar.
    func homeCalendar(limit: Int) async throws -> [CalendarItem] {
        struct Response: Decodable { let items: LossyArray<CalendarItem>?; let pending: Bool? }
        let response: Response = try await send("GET", "\(profilePath)/calendar", query: [
            "days": "14", "recentDays": "90", "compact": "1", "home": "1",
            "limit": String(limit), "tz": TimeZone.current.identifier,
        ], timeout: 60)
        let items = response.items?.elements ?? []
        if response.pending == true, items.isEmpty { throw HomeCalendarPending() }
        return items
    }

    /// Streams playing on the server right now, for the Dashboard row.
    func dashboardStreams() async throws -> [DashboardStream] {
        struct Response: Decodable { let streams: LossyArray<DashboardStream>? }
        let response: Response = try await send("GET", "/api/dashboard/shelf", promptOnLock: false, timeout: 15)
        return response.streams?.elements ?? []
    }

    /// A random title for Watch Something's Surprise Me card (needs an AI key on the server),
    /// of the Home view's media type.
    func surprise(filter: HomeMediaFilter = .all) async throws -> Title {
        struct Pick: Decodable { let title: Title }
        var query = ["userId": profileID]
        if filter != .all { query["mediaType"] = filter.mediaType }
        let item: Pick = try await send("GET", "/api/recommendations/surprise", query: query, timeout: 60)
        return item.title
    }
}

struct HomeSettings {
    /// Every configured shelf, enabled or not, in the profile's order.
    var shelves: [ShelfConfig]
    /// Cards a row shows before its explore card (`itemCap`).
    var itemCap = 20
    /// `exploreCardPosition`: the explore card leads the row unless set to "end".
    var exploreFirst = true
    var hideWatched = false
    /// Continue Watching leaves out shows whose next episode hasn't aired (My Upcoming has them).
    var excludeUpcomingFromContinue = true
    /// Card position, card style and sizes (device settings override them).
    var layout = ProfileHomeLayout()
    var hasAI = false
    /// What leads Home (`tvTopShelfMode`): the promoted Top 10, nothing, or another shelf.
    var topShelfMode = TopShelfMode.standard
    /// The shelf that takes Top 10's place in `.shelf` mode (`tvTopShelfSourceId`).
    var topShelfSourceID: String?
    /// The Home view these settings are resolved for, what it shows, and every view the
    /// profile defines.
    var view = HomeViews.all
    var filter = HomeMediaFilter.all
    var views: HomeViewDefinitions = [:]
}

enum TopShelfMode: String {
    /// The Top 10 promoted into the hero (`default`).
    case standard = "default"
    case disabled
    case shelf
}

/// Home's calendar is still being built on the server (right after a restart): its rows
/// keep loading and retry.
struct HomeCalendarPending: Error {}

/// One release on the profile's calendar (`GET /api/users/{id}/calendar`).
struct CalendarItem: Decodable, Hashable {
    let title: String
    let episodeTitle: String?
    let episodeOverview: String?
    /// movie | series
    let mediaType: String
    let seasonNumber: Int?
    let episodeNumber: Int?
    /// `YYYY-MM-DD`
    let airDate: String
    /// `HH:MM` local to the viewer's time zone (`tz`).
    let airTime: String?
    let network: String?
    /// For movies: theatrical, digital, physical…
    let releaseType: String?
    let posterUrl: String?
    let textPosterUrl: String?
    let backdropUrl: String?
    /// The backdrop with its title text, when `backdropUrl` is textless.
    let textBackdropUrl: String?
    /// Ranked alternate backdrops.
    let backdropUrls: [String]?
    let overview: String?
    let logo: ImageRef?
    let genres: [String]?
    let runtimeMinutes: Int?
    let year: Int?
    let externalIds: [String: String]?
    /// watchlist | history | trending | top-trending | mdblist
    let source: String?

    var isMovie: Bool { mediaType == "movie" }

    /// When it airs, in the viewer's time zone; midnight when the time is unknown.
    var airs: Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = airTime == nil ? "yyyy-MM-dd" : "yyyy-MM-dd HH:mm"
        return formatter.date(from: airTime.map { "\(airDate) \($0)" } ?? airDate)
    }

    /// The details id, built as the Expo app builds it (`buildCalendarTitleId`).
    var titleID: String {
        let ids = externalIds ?? [:]
        if isMovie {
            if let tmdb = ids["tmdb"] { return "tmdb:movie:\(tmdb)" }
            if let imdb = ids["imdb"] { return imdb }
            if let tvdb = ids["tvdb"] { return "tvdb:movie:\(tvdb)" }
        } else {
            if let tmdb = ids["tmdb"] { return "tmdb:tv:\(tmdb)" }
            if let tvdb = ids["tvdb"] { return "tvdb:\(tvdb)" }
            if let imdb = ids["imdb"] { return imdb }
        }
        return title
    }
}

/// A stream playing on the server (`GET /api/dashboard/shelf`).
struct DashboardStream: Decodable, Hashable {
    let id: String
    let profileNames: [String]?
    let percentWatched: Double?
    let isPaused: Bool?
    /// movie | episode
    let mediaType: String?
    let title: String?
    let year: Int?
    let seasonNumber: Int?
    let episodeNumber: Int?
    let episodeName: String?
    let externalIds: [String: String]?
    let posterUrl: String?
    let backdropUrl: String?
    let liveSourceUrl: String?
}
