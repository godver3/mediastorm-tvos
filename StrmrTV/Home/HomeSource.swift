import Foundation

/// Where a shelf's cards come from.
enum HomeSource: Equatable, Sendable {
    case continueWatching
    /// Continue Watching shows whose next episode hasn't aired.
    case upcoming
    case watchlist
    case setAside
    /// A `display-list` source; ranked lists badge their cards "#1", "#2"…
    case list(BrowseList, ranked: Bool)
    /// Recently aired then coming up, from the calendar.
    case calendar
    case recentlyAired(ShelfConfig.CalendarSources?)
    /// What's playing on the server.
    case dashboard
    case watchSomething(hasAI: Bool)
    case services([StreamingService])
    case hub([HubLink])
    /// The profile's favorite live channels.
    case liveFavorites
    /// Today's Top 10 in the hero (`HomeShelf.promotedTopTenID`).
    case promotedTopTen

    struct HubLink: Equatable, Sendable {
        let id: String
        let name: String
        let list: BrowseList
        let art: String?
        let logo: String?
    }

    /// Rows that change after playback or a Continue Watching hide.
    var followsPlayback: Bool {
        switch self {
        case .continueWatching, .upcoming, .setAside, .dashboard: true
        case let .list(list, _): list == .permanentPrequeue
        default: false
        }
    }

    /// Rows built from Home's shared calendar fetch.
    var usesCalendar: Bool {
        switch self {
        case .calendar, .recentlyAired: true
        default: false
        }
    }

    init?(_ config: ShelfConfig, all: [ShelfConfig], settings: HomeSettings) {
        switch config.id {
        case HomeShelf.continueWatchingID: self = .continueWatching
        case "my-upcoming": self = .upcoming
        case "watchlist": self = .watchlist
        case "set-aside": self = .setAside
        case "top-ten": self = .list(.topTen(nil), ranked: true)
        case "my-recommended", "gemini-recs": self = .list(.personalized, ranked: false)
        case "calendar": self = .calendar
        case "my-recently-aired": self = .recentlyAired(config.calendarSources)
        case "dashboard": self = .dashboard
        case "live-favorites": self = .liveFavorites
        case HomeShelf.promotedTopTenID: self = .promotedTopTen
        case "watch-something": self = .watchSomething(hasAI: settings.hasAI)
        case "streaming-services":
            self = .services(StreamingService.resolved(config.streamingServices))
        case "popular-on-server", "recently-watched":
            // The shelf's own window and caps; the explore grid keeps them.
            var query = ["source": config.id, "name": config.title]
            if let days = config.activityWindowDays, days > 0 { query["activityWindowDays"] = String(days) }
            if let min = config.minimumProfiles, min > 0 { query["minimumProfiles"] = String(min) }
            if let max = config.maxItemsPerProfile, max > 0 { query["maxItemsPerProfile"] = String(max) }
            self = .list(.remote(id: config.id, name: config.title, query: query), ranked: false)
        default:
            if config.type == "collection-hub" {
                let byID = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
                let links = (config.collectionItems ?? [])
                    .filter { $0.enabled != false }
                    .sorted { ($0.order ?? 0) < ($1.order ?? 0) }
                    .compactMap { item -> HubLink? in
                        guard let list = item.sourceShelfId.flatMap({ byID[$0] })?.browseList else { return nil }
                        return HubLink(id: item.id, name: item.name ?? list.title, list: list,
                                       art: item.heroArtUrl, logo: item.logoUrl)
                    }
                guard !links.isEmpty else { return nil }
                self = .hub(links)
            } else if let list = config.browseList {
                // Remote lists, trending, genres, decades, permanent prequeue.
                self = .list(list, ranked: false)
            } else {
                return nil
            }
        }
    }
}
