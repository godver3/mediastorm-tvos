import Foundation

/// What the detail panel shows for the focused release (`CalendarItemDetail`): first from
/// the calendar item itself, then filled in by the title's metadata (`CalendarEnrichment`).
struct CalendarItemDetail: Equatable, Sendable {
    let itemKey: String
    let isMovie: Bool
    let title: String
    let episodeTitle: String?
    let episodeLabel: String?
    var synopsis: String
    var backdropURL: String?
    var posterURL: String?
    var year: Int?
    var runtimeMinutes: Int?
    var certification: String?
    var genres: [String]
    var cast: [String]
    /// "9:00 PM", when the release has an air time.
    let airTime: String?

    init(_ item: CalendarItem) {
        itemKey = CalendarModel.itemKey(item)
        isMovie = item.isMovie
        title = item.title
        let episode = item.episodeTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        episodeTitle = episode?.isEmpty == false ? episode : nil
        episodeLabel = CalendarModel.episodeLabel(item)
        synopsis = CalendarModel.summary(item)
        backdropURL = [item.backdropUrl].compactMap { $0 }.first { !$0.isEmpty }
            ?? item.backdropUrls?.first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            ?? [item.textBackdropUrl, item.posterUrl].compactMap { $0 }.first { !$0.isEmpty }
        posterURL = item.posterUrl
        year = item.year
        runtimeMinutes = item.runtimeMinutes
        genres = item.genres ?? []
        cast = []
        airTime = item.airTime.flatMap { $0.isEmpty ? nil : CalendarModel.formatTime($0) }
    }

    /// Fields the metadata filled in replace the calendar's; empty ones don't
    /// (`mergeCalendarItemDetail`).
    func merged(_ enrichment: CalendarEnrichment) -> CalendarItemDetail {
        var detail = self
        if let text = enrichment.synopsis?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            detail.synopsis = text
        }
        if let url = enrichment.backdropURL, !url.isEmpty { detail.backdropURL = url }
        if let year = enrichment.year { detail.year = year }
        if let runtime = enrichment.runtimeMinutes { detail.runtimeMinutes = runtime }
        if let rating = enrichment.certification, !rating.trimmingCharacters(in: .whitespaces).isEmpty {
            detail.certification = rating
        }
        if !enrichment.genres.isEmpty { detail.genres = enrichment.genres }
        if !enrichment.cast.isEmpty { detail.cast = enrichment.cast }
        return detail
    }

    /// The panel's eyebrow: the show's name over an episode title.
    var eyebrow: String? { !isMovie && episodeTitle != nil ? title.uppercased() : nil }

    /// The panel's title: the episode's, else the title's.
    var heading: String { episodeTitle ?? title }

    /// "S1 E4  ·  Released 2024  ·  TV-MA  ·  Airs at 9:00 PM" (`buildMetadataLine`).
    var metadataLine: String {
        let rating = certification?.trimmingCharacters(in: .whitespaces)
        return [episodeLabel, year.map { "Released \($0)" }, rating?.isEmpty == false ? rating : nil,
                airTime.map { "Airs at \($0)" }]
            .compactMap { $0 }.joined(separator: "  ·  ")
    }

    /// Up to four genres, as chips.
    var genreChips: [String] {
        Array(genres.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.prefix(4))
    }

    /// Up to four cast names.
    var castLine: String {
        cast.prefix(4).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: "  ·  ")
    }
}

/// A release's details from `/api/metadata/{movies,series}/details` (`useCalendarItemDetails`).
struct CalendarEnrichment: Equatable, Sendable {
    var synopsis: String?
    var backdropURL: String?
    var year: Int?
    var runtimeMinutes: Int?
    var certification: String?
    var genres: [String] = []
    var cast: [String] = []

    /// `mapMovieEnrichment`: the top eight cast in billing order.
    init(movie: Title) {
        synopsis = movie.overview
        backdropURL = movie.backdrop?.url
        year = movie.year
        runtimeMinutes = movie.runtimeMinutes
        certification = movie.certification
        genres = movie.genres ?? []
        cast = (movie.credits?.cast ?? []).prefix(8).map(\.name)
    }

    /// `mapSeriesEnrichment`: the show's, with the episode's overview and runtime in place
    /// of the show's (the show's overview never replaces the calendar's).
    init(series: SeriesDetails, item: CalendarItem) {
        self.init(movie: series.title)
        let episode = series.seasons.first { $0.number == item.seasonNumber }?
            .episodes.first { $0.episodeNumber == item.episodeNumber }
        let overview = episode?.overview?.trimmingCharacters(in: .whitespacesAndNewlines)
        synopsis = overview?.isEmpty == false ? overview : nil
        runtimeMinutes = episode?.runtimeMinutes
    }

    init() {}
}

/// The timeline over the feed (`CalendarDateTimeline`): a month dot every `spacing`
/// points from the month before the first day to the month after the last, and the
/// active day's position along it.
struct CalendarTimeline: Equatable {
    struct Month: Equatable, Identifiable {
        /// `YYYY-MM`
        let key: String
        /// "OCT"
        let label: String
        var id: String { key }
    }

    let months: [Month]
    let spacing: CGFloat

    init(days: [CalendarDay], spacing: CGFloat) {
        self.spacing = spacing
        let dates = days.map { CalendarModel.date(fromKey: $0.key) }.sorted()
        guard let first = dates.first, let last = dates.last else {
            months = []
            return
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        let start = calendar.dateComponents([.year, .month], from: first)
        let end = calendar.dateComponents([.year, .month], from: last)
        var cursor = calendar.date(from: start).flatMap { calendar.date(byAdding: .month, value: -1, to: $0) }
        let stop = calendar.date(from: end).flatMap { calendar.date(byAdding: .month, value: 1, to: $0) }
        var months: [Month] = []
        while let month = cursor, let stop, month <= stop {
            let parts = calendar.dateComponents([.year, .month], from: month)
            months.append(Month(key: String(format: "%04d-%02d", parts.year ?? 0, parts.month ?? 1),
                                label: month.formatted(.dateTime.month(.abbreviated)).uppercased()))
            cursor = calendar.date(byAdding: .month, value: 1, to: month)
        }
        self.months = months
    }

    /// The track's width: at least one spacing.
    var width: CGFloat { max(spacing, CGFloat(months.count - 1) * spacing + 1) }

    /// Where a day sits on the track: its month's dot plus the day's share of the month
    /// (`getActivePosition`).
    func position(of dateKey: String) -> CGFloat {
        let date = CalendarModel.date(fromKey: dateKey)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        let key = String(format: "%04d-%02d", parts.year ?? 0, parts.month ?? 1)
        let index = max(0, months.firstIndex { $0.key == key } ?? 0)
        let daysInMonth = calendar.range(of: .day, in: .month, for: date)?.count ?? 30
        let share = CGFloat((parts.day ?? 1) - 1) / CGFloat(max(1, daysInMonth - 1))
        return CGFloat(index) * spacing + share * spacing
    }
}
