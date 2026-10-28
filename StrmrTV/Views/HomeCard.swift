import Foundation

/// What selecting a Home card does.
enum HomeLink: Hashable {
    /// A title's details page.
    case details(DetailsTarget)
    /// A whole list (streaming service, collection hub card).
    case list(BrowseList)
    /// A Watch Something card.
    case action(HomeAction)
    /// A favorite channel (and what it airs now): tunes it in the live player.
    case channel(LiveChannel, program: EPGProgram?)
    /// An unmatched library title, which has no details page: plays the file, or opens the
    /// show's library episodes (`LibraryEntryLink`). Matched library titles open `details`.
    case library(LibraryEntry)
}

enum HomeAction: String, Hashable {
    /// Opens the Search tab.
    case search
    /// Asks the server for a random pick and opens its details.
    case surprise
    /// Asks the server's AI for titles matching a description, shown as a list.
    case askAI
}

/// One Home card, from any shelf: what the card, the hero and details need.
struct HomeCard: Identifiable, Hashable {
    let id: String
    let link: HomeLink
    let title: String
    /// Under the title on the card, and under the logo in the hero.
    let subtitle: String
    let overview: String?
    let backdropURL: String?
    let logoURL: String?
    /// Card image: the next episode's still for Continue Watching, else the backdrop.
    let artworkURL: String?
    /// For the explore card's collage.
    var posterURL: String?
    /// 0–1; 0 hides the bar.
    let progress: Double
    /// Rank, release status or air date: shown first.
    let badge: CardBadge?
    /// Watched or in progress, shown beside `badge` (a watched title can still be in theaters).
    var watchBadge: CardBadge?
    /// "New": Continue Watching's next episode came out in the last 72 hours.
    var newEpisode: NewEpisodeBadge?
    /// The card draws `logoURL` on a plain tile instead of artwork (services, hubs).
    var logoTile = false
    /// An SF Symbol drawn on a plain tile (Watch Something).
    var symbol: String?
    /// The content rating and genres, for the Home carousel's line (list titles only).
    var certification: String?
    var genres: [String] = []
    /// The one episode the card stands for, for its long press's Mark as Watched.
    var episode: CardEpisode?

    var target: DetailsTarget? {
        if case let .details(target) = link { target } else { nil }
    }

    init(_ item: ContinueWatchingItem) {
        id = item.id
        link = .details(DetailsTarget(item))
        posterURL = item.textPosterUrl ?? item.posterUrl
        title = item.seriesTitle
        if item.isMovie {
            subtitle = item.year.map(String.init) ?? String(localized: "Movie")
        } else if let ep = item.nextEpisode {
            subtitle = ep.code + (ep.title.map { " · \($0)" } ?? "")
        } else {
            subtitle = String(localized: "Series")
        }
        overview = item.nextEpisode?.overview ?? item.overview
        backdropURL = item.backdropUrl
        logoURL = item.logoUrl
        artworkURL = item.nextEpisode?.image?.url ?? item.backdropUrl
        // The server's resume state for the item the row plays (movie, or next episode);
        // older servers send only the raw percentages.
        if let resume = item.resume {
            progress = resume.eligible ? resume.fraction : 0
        } else {
            let pct = item.isMovie ? (item.percentWatched ?? 0) : (item.resumePercent ?? 0)
            progress = min(max(pct / 100, 0), 1)
        }
        // Unaired next episode beats the series status; movies use their release status.
        if !item.isMovie, let ep = item.nextEpisode,
           let airs = ReleaseBadge.forEpisode(airDate: ep.airDate, airDateTimeUTC: ep.airDateTimeUTC) {
            badge = CardBadge(text: airs)
        } else {
            badge = ReleaseBadge.forTitle(status: item.status)
        }
        if !item.isMovie, let ep = item.nextEpisode {
            episode = CardEpisode(ep)
            newEpisode = NewEpisodeBadge(airDate: ep.airDate, airDateTimeUTC: ep.airDateTimeUTC,
                                         prequeueStatus: item.prequeueStatus)
        }
    }

    init(_ item: WatchlistItem) {
        id = item.id
        link = .details(DetailsTarget(item))
        posterURL = item.textPosterUrl ?? item.posterUrl
        title = item.name
        subtitle = Self.kindLine(year: item.year, isMovie: item.isMovie)
        overview = item.overview
        backdropURL = item.backdropUrl
        logoURL = item.logoUrl
        artworkURL = item.backdropUrl ?? item.posterUrl
        progress = 0
        badge = ReleaseBadge.forTitle(item)
        watchBadge = CardBadge.forWatchState(item.watchState)
    }

    /// A list title; `rank` (Top 10) shows as the first badge.
    init(_ title: Title, rank: Int? = nil) {
        id = title.id
        link = .details(DetailsTarget(title))
        posterURL = title.textPoster?.url ?? title.poster?.url
        self.title = title.name
        subtitle = Self.kindLine(year: title.year, isMovie: title.isMovie)
        overview = title.overview
        backdropURL = title.backdrop?.url
        logoURL = title.logo?.url
        artworkURL = title.backdrop?.url ?? title.poster?.url
        progress = 0
        badge = rank.map { CardBadge(text: "#\($0)") } ?? ReleaseBadge.forTitle(title)
        watchBadge = CardBadge.forWatchState(title.watchState)
        certification = title.certification
        genres = title.genres ?? []
    }

    init(_ entry: BrowseEntry) {
        switch entry {
        case let .title(title): self.init(title)
        case let .item(item): self.init(item)
        case let .library(entry): self.init(library: entry)
        }
    }

    /// A library title (Home library rows, library grids).
    init(library entry: LibraryEntry) {
        let group = entry.group
        id = entry.id
        link = entry.detailsTarget.map(HomeLink.details) ?? .library(entry)
        posterURL = group.posterURL
        title = group.title
        subtitle = Self.kindLine(year: group.year, isMovie: !group.isShow)
        overview = group.overview
        backdropURL = group.backdropURL
        logoURL = nil
        artworkURL = group.backdropURL ?? group.posterURL
        progress = 0
        badge = nil
    }

    /// A card that isn't a title: a service or hub tile, or a Watch Something action.
    init(id: String, link: HomeLink, title: String, subtitle: String, overview: String? = nil,
         backdropURL: String? = nil, logoURL: String? = nil, logoTile: Bool = false, symbol: String? = nil) {
        self.id = id
        self.link = link
        self.title = title
        self.subtitle = subtitle
        self.overview = overview
        self.backdropURL = backdropURL
        self.logoURL = logoURL
        artworkURL = backdropURL
        progress = 0
        badge = nil
        self.logoTile = logoTile
        self.symbol = symbol
    }

    /// Everything given, for cards built from other server shapes (calendar, dashboard).
    init(id: String, target: DetailsTarget, title: String, subtitle: String, overview: String?,
         artworkURL: String?, progress: Double = 0, badge: CardBadge? = nil) {
        self.id = id
        link = .details(target)
        self.title = title
        self.subtitle = subtitle
        self.overview = overview
        backdropURL = target.backdropURL
        logoURL = target.logoURL
        self.artworkURL = artworkURL
        posterURL = target.displayPosterURL
        self.progress = progress
        self.badge = badge
    }

    static func kindLine(year: Int?, isMovie: Bool) -> String {
        [year.map(String.init), isMovie ? String(localized: "Movie") : String(localized: "Series")]
            .compactMap { $0 }.joined(separator: " · ")
    }
}

/// A Home row, one per enabled shelf of the profile's `homeShelves` config. It shows
/// its first `cap` cards; a longer list gets an explore card that opens the whole list.
struct HomeShelf: Identifiable, Equatable {
    static let continueWatchingID = "continue-watching"
    /// The Top 10 promoted into the hero: its own identity, apart from the `top-ten` row.
    static let promotedTopTenID = "tv-promoted-top-ten"

    /// The shelf config's id.
    let id: String
    let title: String
    /// The cards loaded for the row: the shown ones plus any overflow for the collage.
    let cards: [HomeCard]
    /// The whole list's size, which is larger than `cards` when the server pages it.
    let total: Int
    let cap: Int
    let explore: ExploreCard?
    /// The explore card leads the row instead of closing it (`exploreCardPosition`).
    let exploreFirst: Bool

    init(id: String, title: String, cards: [HomeCard], total: Int? = nil, cap: Int = 20,
         list: BrowseList? = nil, exploreFirst: Bool = false) {
        self.id = id
        self.title = title
        self.cards = cards
        self.cap = cap
        let total = max(total ?? cards.count, cards.count)
        self.total = total
        self.exploreFirst = exploreFirst
        explore = total > cap ? list.map { ExploreCard(shelf: id, title: title, list: $0, cards: cards, cap: cap, total: total) } : nil
    }

    var shown: ArraySlice<HomeCard> { cards.prefix(cap) }

    /// Focus ids in on-screen order: the cards and the explore card where it sits.
    var focusOrder: [String] {
        let ids = shown.map(\.id)
        guard explore != nil else { return ids }
        return exploreFirst ? [ExploreCard.id] + ids : ids + [ExploreCard.id]
    }
}

/// The card on a Home row holding more than its cap: a 2×2 grid of posters from titles
/// the row does not show, and how many more there are. It opens the whole list.
struct ExploreCard: Equatable {
    static let id = "__explore__"

    let shelf: String
    let title: String
    let list: BrowseList
    let moreCount: Int
    let total: Int
    let posterURLs: [String]
    /// The same pick from the titles' 16:9 art, for the card when it is 16:9.
    let artworkURLs: [String]
    /// The hero's backdrop while the card has focus: the first hidden title's.
    let backdropURL: String?

    init(shelf: String, title: String, list: BrowseList, cards: [HomeCard], cap: Int, total: Int) {
        self.shelf = shelf
        self.title = title
        self.list = list
        self.total = total
        moreCount = total - cap
        let overflow = cards.dropFirst(cap)
        backdropURL = overflow.lazy.compactMap(\.backdropURL).first ?? cards.first?.backdropURL
        posterURLs = Self.collage(\.posterURL, shown: cards.prefix(cap), overflow: overflow, seed: shelf)
        artworkURLs = Self.collage(\.artworkURL, shown: cards.prefix(cap), overflow: overflow, seed: shelf)
    }

    /// Four images (posters, or 16:9 art) from the hidden titles, skipping any already
    /// shown, picked by a shuffle seeded from the row and its posters so the card stays the same between
    /// renders and launches (as the Expo app's `pickExploreCollageImages` does). Falls
    /// back to the last shown titles when too few are hidden.
    private static func collage(_ image: KeyPath<HomeCard, String?>, shown: ArraySlice<HomeCard>,
                                overflow: ArraySlice<HomeCard>, seed: String) -> [String] {
        var seen = Set(shown.compactMap { $0[keyPath: image] })
        let hidden = overflow.compactMap { $0[keyPath: image] }.filter { seen.insert($0).inserted }
        var generator = SeededGenerator(seed: ([seed] + hidden.prefix(10)).joined())
        var picked = Array(hidden.shuffled(using: &generator).prefix(4))
        if picked.count < 4 {
            var fill = Set(picked)
            picked += shown.reversed().compactMap { $0[keyPath: image] }.filter { fill.insert($0).inserted }.prefix(4 - picked.count)
        }
        return picked
    }
}

/// SplitMix64 seeded from an FNV-1a hash of a string: a shuffle that repeats.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: String) {
        state = seed.utf8.reduce(0xcbf2_9ce4_8422_2325) { ($0 ^ UInt64($1)) &* 0x100_0000_01b3 }
    }

    mutating func next() -> UInt64 {
        state &+= 0x9e37_79b9_7f4a_7c15
        var z = state
        z = (z ^ (z >> 30)) &* 0xbf58_476d_1ce4_e5b9
        z = (z ^ (z >> 27)) &* 0x94d0_49bb_1331_11eb
        return z ^ (z >> 31)
    }
}

/// A focused card: the same title can sit in more than one row.
struct HomeFocus: Hashable {
    let shelf: String
    let card: String
}

/// Where focus was on a Home view's page, kept by its store: the side menu rebuilds a tab's
/// page each time the tab is chosen again, which forgot the card left and put focus on the
/// first row's first card.
struct HomeFocusMemory {
    var hero: HomeFocus?
    var lastRow: HomeFocus?
    var rows: [String: String]
    var carouselIndex: Int
}
