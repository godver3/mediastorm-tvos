import Foundation

/// Calendar releases as Home cards: a show's episodes airing together are one card
/// ("S02E01 +2"), as in the Expo app's `groupCalendarItems`.
struct CalendarGroup {
    /// The earliest episode of the group (or the movie).
    let first: CalendarItem
    var count = 1

    var airs: Date? { first.airs }

    /// Every release, grouped, in the server's order.
    static func group(_ items: [CalendarItem]) -> [CalendarGroup] {
        var groups: [CalendarGroup] = []
        var index: [String: Int] = [:]
        for item in items {
            guard !item.isMovie else {
                groups.append(CalendarGroup(first: item))
                continue
            }
            let key = [item.titleID, item.airDate, item.airTime ?? "", item.network ?? ""].joined(separator: "|")
            if let at = index[key] {
                let current = groups[at].first
                let mine: (Int, Int) = (item.seasonNumber ?? .max, item.episodeNumber ?? .max)
                let theirs: (Int, Int) = (current.seasonNumber ?? .max, current.episodeNumber ?? .max)
                let earlier = mine < theirs
                groups[at] = CalendarGroup(first: earlier ? item : current, count: groups[at].count + 1)
            } else {
                index[key] = groups.count
                groups.append(CalendarGroup(first: item))
            }
        }
        return groups
    }

    /// The Coming Up row: the latest of what already aired, then up to four upcoming
    /// releases (`splitCalendarItems`).
    static func comingUp(_ groups: [CalendarGroup], limit: Int) -> [CalendarGroup] {
        guard limit > 0 else { return [] }
        let now = Date.now
        let aired = groups.filter { ($0.airs ?? .distantFuture) <= now }
        let upcoming = groups.filter { ($0.airs ?? .distantPast) > now }
        if aired.isEmpty { return Array(upcoming.prefix(limit)) }
        if upcoming.isEmpty { return Array(aired.suffix(limit)) }
        let reserved = min(4, limit - 1, upcoming.count)
        let recent = min(aired.count, limit - reserved)
        return Array(aired.suffix(recent)) + upcoming.prefix(limit - recent)
    }

    /// Whether the shelf's `calendarSources` take this release (watchlist only when unset).
    func matches(_ sources: ShelfConfig.CalendarSources?) -> Bool {
        guard let sources else { return first.source == "watchlist" }
        return switch first.source {
        case "watchlist": sources.watchlist == true
        case "history": sources.history == true
        case "trending": sources.trending == true
        case "top-trending": sources.topTrending == true
        case "mdblist": sources.mdblists == true
        default: false
        }
    }

    var card: HomeCard {
        let item = first
        let episode: String? = item.seasonNumber.flatMap { season in
            item.episodeNumber.map { String(format: "S%02dE%02d", season, $0) + (count > 1 ? " +\(count - 1)" : "") }
        }
        let release = item.isMovie ? item.releaseType.map(Self.releaseLabel) : episode
        let subtitle = [release, dayLabel].compactMap { $0 }.joined(separator: " · ")
        let overview = count == 1 ? (item.episodeOverview ?? item.overview) : item.overview
        var card = HomeCard(id: "\(item.titleID)@\(item.airDate)", target: DetailsTarget(item),
                            title: item.title, subtitle: subtitle, overview: overview,
                            artworkURL: item.backdropUrl ?? item.posterUrl)
        // A day's several episodes keep only the bulk screen.
        if count == 1 { card.episode = CardEpisode(item) }
        return card
    }

    /// "Today 9:00 PM", "Tomorrow", "Tue, Oct 14".
    private var dayLabel: String {
        guard let airs else { return first.airDate }
        let calendar = Calendar.current
        let time = first.airTime == nil ? nil : airs.formatted(date: .omitted, time: .shortened)
        let day = if calendar.isDateInToday(airs) {
            String(localized: "Today")
        } else if calendar.isDateInTomorrow(airs) {
            String(localized: "Tomorrow")
        } else if calendar.isDateInYesterday(airs) {
            String(localized: "Yesterday")
        } else {
            airs.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        }
        return [day, time].compactMap { $0 }.joined(separator: " ")
    }

    private static func releaseLabel(_ type: String) -> String {
        switch type {
        case "premiere": String(localized: "Premiere")
        case "theatricalLimited": String(localized: "Limited Theatrical")
        case "theatrical": String(localized: "In Theaters")
        case "digital": String(localized: "Digital")
        case "physical": String(localized: "Physical")
        case "tv": String(localized: "TV")
        case "streaming": String(localized: "Streaming")
        default: type.capitalized
        }
    }
}

extension DetailsTarget {
    init(_ item: CalendarItem) {
        titleID = item.titleID
        name = item.title
        isMovie = item.isMovie
        year = item.year
        tmdbID = item.externalIds?["tmdb"]
        imdbID = item.externalIds?["imdb"]
        tvdbID = item.externalIds?["tvdb"]
        posterURL = item.posterUrl
        textPosterURL = item.textPosterUrl
        backdropURL = item.backdropUrl
        logoURL = item.logo?.url
        overview = item.overview
    }

    /// A dashboard stream's title; nil for live channels and streams without IDs.
    init?(_ stream: DashboardStream) {
        guard stream.liveSourceUrl?.isEmpty != false, let title = stream.title, let ids = stream.externalIds else { return nil }
        let movie = stream.mediaType == "movie"
        if let tmdb = ids["tmdb"] {
            titleID = movie ? "tmdb:movie:\(tmdb)" : "tmdb:tv:\(tmdb)"
        } else if let tvdb = ids["tvdb"] {
            titleID = movie ? "tvdb:movie:\(tvdb)" : "tvdb:\(tvdb)"
        } else if let imdb = ids["imdb"] {
            titleID = imdb
        } else {
            return nil
        }
        name = title
        isMovie = movie
        year = stream.year
        tmdbID = ids["tmdb"]
        imdbID = ids["imdb"]
        tvdbID = ids["tvdb"]
        posterURL = stream.posterUrl
        textPosterURL = nil
        backdropURL = stream.backdropUrl
        logoURL = nil
        overview = nil
    }
}

extension HomeCard {
    /// A stream playing on the server: who is watching, and how far in.
    init?(_ stream: DashboardStream) {
        guard let target = DetailsTarget(stream) else { return nil }
        let episode: String? = stream.seasonNumber.flatMap { season in
            stream.episodeNumber.map { String(format: "S%02dE%02d", season, $0) }
        }
        let state = stream.isPaused == true ? String(localized: "Paused") : String(localized: "Playing")
        let who = stream.profileNames?.joined(separator: ", ")
        let subtitle = [state, who?.isEmpty == false ? who : nil, episode].compactMap { $0 }.joined(separator: " · ")
        self.init(id: stream.id, target: target, title: target.name, subtitle: subtitle,
                  overview: stream.episodeName, artworkURL: stream.backdropUrl ?? stream.posterUrl,
                  progress: min(max((stream.percentWatched ?? 0) / 100, 0), 1))
    }
}
