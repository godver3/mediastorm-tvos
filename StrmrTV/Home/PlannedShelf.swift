import Foundation

/// A configured shelf the app can show, and where its cards come from.
struct PlannedShelf: Identifiable, Sendable {
    let config: ShelfConfig
    let source: HomeSource
    /// Cards the row shows before its explore card.
    let cap: Int
    /// The shelf's own limit is below the cap: the row is the whole list, no explore card.
    let limited: Bool
    let exploreFirst: Bool

    var id: String { config.id }

    /// The enabled shelves in order, minus those the app can't show yet (watch rooms,
    /// libraries) and those a kids profile doesn't get. A curated kids profile gets a row per
    /// allowed list instead of the open-ended ones (trending, Top 10, streaming services).
    static func plan(_ settings: HomeSettings, profile: Profile?) -> [PlannedShelf] {
        let isKids = profile?.isKidsProfile == true
        let curated = profile?.isKidsCurated == true
        var all = Self.applyTopShelf(settings.shelves, settings: settings, promote: !curated)
        if let profile, curated {
            all.removeAll { Self.notForCuratedKids.contains($0.id) }
            all = (all + Self.kidsListShelves(profile.kidsAllowedLists ?? [])).sorted { ($0.order ?? 0) < ($1.order ?? 0) }
        }
        var seen = Set<String>()
        #if DEBUG
        let forced = DebugPrefill.enabledShelves
        #else
        let forced = Set<String>()
        #endif
        return all.compactMap { config in
            guard config.enabled == true || forced.contains(config.id), seen.insert(config.id).inserted,
                  !(isKids && config.id == "watch-something"),
                  let source = HomeSource(config, all: all, settings: settings) else { return nil }
            let limit = config.limit ?? 0
            let limited = limit > 0 && limit < settings.itemCap
            return PlannedShelf(config: config, source: source, cap: limited ? limit : settings.itemCap,
                                limited: limited, exploreFirst: settings.exploreFirst)
        }
    }

    private static let notForCuratedKids: Set = ["trending-movies", "trending-tv", "top-ten", "streaming-services"]
    private static let topTenID = "top-ten"
    /// The promoted Top 10 hero (`PromotedTopTenRow`) is parked: Home keeps the plain
    /// `top-ten` row for now (decided 2026-10-18).
    private static let promotesTopTen = false

    /// The Expo TV top shelf (`tvTopShelfMode`). Default: Today's Top 10 leads in the hero
    /// (while `promotesTopTen`), and the `top-ten` row goes when it would be the first row
    /// anyway; otherwise the row stays as configured. Disabled: no Top 10.
    /// Shelf: another configured shelf takes Top 10's place.
    private static func applyTopShelf(_ shelves: [ShelfConfig], settings: HomeSettings, promote: Bool) -> [ShelfConfig] {
        switch settings.topShelfMode {
        case .disabled:
            return shelves.filter { $0.id != topTenID }
        case .shelf:
            guard let sourceID = settings.topShelfSourceID, sourceID != topTenID,
                  var source = shelves.first(where: { $0.id == sourceID }) else { return shelves }
            source.enabled = true
            source.order = shelves.first { $0.id == topTenID }?.order ?? min(shelves.compactMap(\.order).min() ?? 0, 0)
            let rest = shelves.filter { $0.id != sourceID && $0.id != topTenID }
            return ([source] + rest).sorted { ($0.order ?? 0) < ($1.order ?? 0) }
        case .standard:
            guard promote, promotesTopTen else { return shelves }
            let first = shelves.filter { $0.enabled == true && $0.id != "watch-together" }.first
            let name = shelves.first { $0.id == topTenID }?.name ?? String(localized: "Top 10 Today")
            guard let promoted = ShelfConfig.make(["id": HomeShelf.promotedTopTenID, "name": name, "enabled": true,
                                               "order": Int(Int32.min)]) else { return shelves }
            return [promoted] + shelves.filter { $0.id != topTenID || first?.id != topTenID }
        }
    }

    /// The Expo app's `kids-list-N` shelves: MDBList rows named after the URL's last segment.
    private static func kidsListShelves(_ urls: [String]) -> [ShelfConfig] {
        urls.enumerated().compactMap { index, url in
            let slug = url.components(separatedBy: "/").last ?? ""
            let name = slug.isEmpty ? String(localized: "Kids List \(index + 1)")
                : slug.split(whereSeparator: { $0 == "-" || $0 == "_" }).map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
            return ShelfConfig.make(["id": "kids-list-\(index)", "type": "mdblist", "listUrl": url, "name": name,
                                 "enabled": true, "order": 10 + index])
        }
    }

    func row(_ cards: [HomeCard], total: Int? = nil, list: BrowseList? = nil) -> HomeShelf {
        HomeShelf(id: id, title: config.title, cards: cards, total: limited ? min(cards.count, cap) : total,
                         cap: cap, list: limited ? nil : list, exploreFirst: exploreFirst)
    }

    func watchlistRow(_ items: [WatchlistItem], settings: HomeSettings) -> HomeShelf {
        let shown = items.filter { HomeViews.matches(mediaType: $0.mediaType, settings.filter) }
            .filter { !settings.hideWatched || $0.watchState != "complete" }
        return row(shown.map(HomeCard.init), list: .watchlist)
    }

    /// A JPEG shipped in the app bundle, as a URL string the image pipeline loads.
    private static func bundledArt(_ name: String) -> String? {
        Bundle.main.url(forResource: name, withExtension: "jpg")?.absoluteString
    }

    /// Cards a progressive row's first pass asks for, a screenful or two; a large `itemCap`
    /// waits for the complete pass.
    static let firstPage = 30

    /// A progressive list: the first cards come fast, then a second pass fills them in.
    var completesLater: Bool {
        if case let .list(list, _) = source { list.loadsProgressively } else { false }
    }

    /// Cards the row asks for: its cap, plus the explore card's collage when the list runs on.
    private var wanted: Int { limited ? cap : cap + HomeShelf.collageOverflow }

    /// A progressive row too long for one quick pass: its first cards are a `firstPage`,
    /// its complete pass the rest.
    var startsPartial: Bool { completesLater && wanted > Self.firstPage }

    /// The row's cards. `phase` applies to progressive lists (`completesLater`).
    func load(_ context: HomeContext, phase: ShelfPhase = .cards) async throws -> HomeShelf? {
        let settings = context.settings
        switch source {
        case .continueWatching:
            var items = try await context.continueWatching()
            if settings.excludeUpcomingFromContinue { items = items.filter { !$0.isUpcoming } }
            return row(items.map(HomeCard.init), list: .continueWatching)

        case .upcoming:
            let items = try await context.continueWatching().filter(\.isUpcoming)
            let sorted = switch config.sort {
            case "air-date-desc": items.sorted { $0.airs > $1.airs }
            case "title": items.sorted { $0.seriesTitle.localizedStandardCompare($1.seriesTitle) == .orderedAscending }
            case "recently-watched": items
            default: items.sorted { $0.airs < $1.airs }
            }
            return HomeShelf(id: id, title: config.title, cards: sorted.prefix(cap).map(HomeCard.init), cap: cap)

        case .watchlist:
            return nil  // built by the store from `WatchlistStore`

        case .setAside:
            let lists = try await APIClient.shared.customLists()
            guard let list = lists.first(where: \.isSetAside) else { return nil }
            let items = try await APIClient.shared.customListItems(id: list.id)
                .filter { HomeViews.matches(mediaType: $0.mediaType, settings.filter) }
            return row(items.map(HomeCard.init), list: .custom(id: list.id, name: list.name))

        case let .list(list, ranked):
            var extra: [String: String] = ["name": config.title]
            if config.hideUnreleased == true { extra["hideUnreleased"] = "true" }
            if settings.hideWatched { extra["hideWatched"] = "true" }
            // The server filters the list to the Home view's media type.
            if settings.view != HomeViews.all { extra["homeView"] = settings.view }
            // A progressive row's first pass asks for a screenful; its complete pass fills the row.
            let partial = phase == .cards && startsPartial
            let page = try await APIClient.shared.browsePage(list, limit: partial ? Self.firstPage : wanted,
                                                             extra: extra, phase: phase)
            let cards = page.entries.enumerated().map { index, entry in
                if ranked, case let .title(title) = entry { HomeCard(title, rank: index + 1) } else { HomeCard(entry) }
            }
            guard partial else { return row(cards, total: page.total, list: list) }
            // Until then the explore card follows the first cards, so the whole list is a click
            // away even if the complete pass is slow or fails.
            return HomeShelf(id: id, title: config.title, cards: cards, total: limited ? cards.count : page.total,
                             cap: cards.count, list: limited ? nil : list, exploreFirst: exploreFirst)

        case .calendar:
            let items = CalendarGroup.group(try await context.calendar())
            return HomeShelf(id: id, title: config.title, cards: CalendarGroup.comingUp(items, limit: cap).map(\.card), cap: cap)

        case let .recentlyAired(sources):
            let now = Date.now
            let items = CalendarGroup.group(try await context.calendar())
                .filter { !$0.first.isMovie && $0.matches(sources) && ($0.airs ?? .distantFuture) <= now }
                .sorted { ($0.airs ?? .distantPast) > ($1.airs ?? .distantPast) }
            return HomeShelf(id: id, title: config.title, cards: items.prefix(cap).map(\.card), cap: cap)

        case .dashboard:
            let streams = try await APIClient.shared.dashboardStreams()
            return HomeShelf(id: id, title: config.title, cards: streams.compactMap(HomeCard.init), cap: cap)

        case let .watchSomething(hasAI):
            // The hero shows the Expo home's art for each action, bundled with the app.
            var cards = [HomeCard(id: HomeShelf.watchSomethingSearchID, link: .action(.search),
                                  title: String(localized: "Search"), subtitle: String(localized: "Find a title"),
                                  overview: String(localized: "Look up a movie, show or person."),
                                  backdropURL: Self.bundledArt("watch-something-search"),
                                  symbol: "magnifyingglass")]
            if hasAI {
                cards.append(HomeCard(id: "__watch_something_ai__", link: .action(.askAI),
                                      title: String(localized: "Ask AI"),
                                      subtitle: String(localized: "Describe what you want"),
                                      overview: String(localized: "Tell the server's AI what you're in the mood for and get a list to pick from."),
                                      backdropURL: Self.bundledArt("watch-something-ask-ai"),
                                      symbol: "sparkles"))
                cards.append(HomeCard(id: "__watch_something_surprise__", link: .action(.surprise),
                                      title: String(localized: "Surprise Me"),
                                      subtitle: String(localized: "A random pick"),
                                      overview: String(localized: "Let the server pick something for tonight."),
                                      backdropURL: Self.bundledArt("watch-something-surprise"),
                                      symbol: "dice"))
            }
            return HomeShelf(id: id, title: config.title, cards: cards, cap: cap)

        case let .services(services):
            let cards = services.map { service in
                HomeCard(id: "service-\(service.id)", link: .list(.service(service)), title: service.name,
                         subtitle: String(localized: "Top movies and shows"), logoURL: service.logoUrl, logoTile: true)
            }
            return HomeShelf(id: id, title: config.title, cards: cards, cap: cap)

        case let .hub(links):
            let cards = links.map { link in
                HomeCard(id: "hub-\(link.id)", link: .list(link.list), title: link.name,
                         subtitle: link.list.title, backdropURL: link.art,
                         logoURL: link.logo, logoTile: link.art == nil)
            }
            return HomeShelf(id: id, title: config.title, cards: cards, cap: cap)

        case .liveFavorites:
            let cards = try await APIClient.shared.favoriteChannelCards(limit: cap)
            return HomeShelf(id: id, title: config.title, cards: cards, cap: cap)

        case .promotedTopTen:
            // Ten ranked titles, no explore card: the hero steps through them.
            var extra = ["name": config.title]
            if settings.view != HomeViews.all { extra["homeView"] = settings.view }
            let page = try await APIClient.shared.browsePage(.topTen(nil), limit: 10, extra: extra, phase: phase)
            let cards = page.entries.enumerated().map { index, entry in
                if case let .title(title) = entry { HomeCard(title, rank: index + 1) } else { HomeCard(entry) }
            }
            return HomeShelf(id: id, title: config.title, cards: cards, cap: 10)
        }
    }
}

/// What several rows share within one load: fetched once, on first use. Continue Watching
/// and the calendar come filtered to the Home view's media type (`matchesHomeView`).
final class HomeContext: @unchecked Sendable {
    let settings: HomeSettings
    private let continueWatchingTask: Task<[ContinueWatchingItem], Error>?
    private let calendarTask: Task<[CalendarItem], Error>?

    init(settings: HomeSettings, plan: [PlannedShelf]) {
        self.settings = settings
        let sources = plan.map(\.source)
        continueWatchingTask = sources.contains { $0 == .continueWatching || $0 == .upcoming }
            ? Task { try await APIClient.shared.continueWatching() } : nil
        let usesCalendar = sources.contains { if case .calendar = $0 { true } else if case .recentlyAired = $0 { true } else { false } }
        let calendarLimit = max(plan.map(\.cap).max() ?? 20, 20)
        calendarTask = usesCalendar ? Task { try await APIClient.shared.homeCalendar(limit: calendarLimit) } : nil
    }

    var loadsContinueWatching: Bool { continueWatchingTask != nil }
    /// Every Continue Watching item, whatever the view (for the Top Shelf).
    func allContinueWatching() async throws -> [ContinueWatchingItem] { try await continueWatchingTask?.value ?? [] }
    func continueWatching() async throws -> [ContinueWatchingItem] {
        try await allContinueWatching().filter {
            HomeViews.matches(mediaType: $0.nextEpisode == nil ? "movie" : "series", settings.filter)
        }
    }
    func calendar() async throws -> [CalendarItem] {
        try await (calendarTask?.value ?? []).filter { HomeViews.matches(mediaType: $0.mediaType, settings.filter) }
    }
}

extension HomeShelf {
    /// Titles fetched beyond a row's cap, for the explore card's collage.
    static let collageOverflow = 8

    static let watchSomethingSearchID = "__watch_something_search__"

    func removing(card: String) -> HomeShelf {
        HomeShelf(id: id, title: title, cards: cards.filter { $0.id != card }, total: total - 1, cap: cap,
                  list: explore?.list, exploreFirst: exploreFirst)
    }
}

extension ContinueWatchingItem {
    /// A show whose next episode hasn't aired yet.
    var isUpcoming: Bool { !isMovie && airs > .now }

    /// When the next episode airs; distant past when unknown (already watchable).
    var airs: Date {
        guard let ep = nextEpisode else { return .distantPast }
        if let exact = ep.airDateTimeUTC, let date = try? Date(exact, strategy: .iso8601) { return date }
        return ReleaseBadge.parseDay(ep.airDate) ?? .distantPast
    }
}
