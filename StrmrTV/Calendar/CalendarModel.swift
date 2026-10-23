import Foundation

/// A port of the Expo app's `calendar-model.ts`: the Calendar screen's grouping into days,
/// its default selection and the text it shows. Pure, so `CalendarModelTests` covers it.

/// Which releases a day list keeps (`CalendarFilter`).
enum CalendarFilter: String, Sendable {
    case all, upcoming, recent, series, movies
}

/// The calendar `source=` the server is asked for (`SourceFilter`); `all` sends none.
enum CalendarSource: String, Sendable {
    case all, watchlist, history, trending
    case topTrending = "top-trending"
    case mdblist
}

/// The TV rail's categories, in Expo's order (`CALENDAR_NAV_ITEMS`).
enum CalendarCategory: String, CaseIterable, Identifiable, Sendable {
    case all, tv, movies, trending, watchlist, top

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: String(localized: "All")
        case .tv: String(localized: "TV")
        case .movies: String(localized: "Movies")
        case .trending: String(localized: "Trending")
        case .watchlist: String(localized: "Watchlist")
        case .top: String(localized: "Top")
        }
    }

    var filter: CalendarFilter {
        switch self {
        case .tv: .series
        case .movies: .movies
        default: .all
        }
    }

    var source: CalendarSource {
        switch self {
        case .trending: .trending
        case .watchlist: .watchlist
        case .top: .topTrending
        default: .all
        }
    }
}

/// One day of the feed: its `YYYY-MM-DD` key and releases, earliest first.
struct CalendarDay: Identifiable, Equatable, Sendable {
    let key: String
    let items: [CalendarItem]
    var id: String { key }
}

struct CalendarSelection: Equatable, Sendable {
    var dateKey: String?
    var itemKey: String?
}

enum CalendarModel {
    /// A release's identity within the calendar (`buildCalendarItemKey`).
    static func itemKey(_ item: CalendarItem) -> String {
        let ids = item.externalIds ?? [:]
        let identity = ids["tmdb"].map { "tmdb:\($0)" }
            ?? ids["tvdb"].map { "tvdb:\($0)" }
            ?? ids["imdb"]
            ?? item.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return [identity, item.mediaType, item.airDate, String(item.seasonNumber ?? 0),
                String(item.episodeNumber ?? 0), item.releaseType ?? ""].joined(separator: ":")
    }

    /// Releases with an air date that pass `filter`, by day, earliest first; within a day
    /// by air time, all-day releases last (`groupCalendarDays`).
    static func groupDays(_ items: [CalendarItem], filter: CalendarFilter, todayKey: String) -> [CalendarDay] {
        let kept = items.enumerated().filter { _, item in
            guard !item.airDate.isEmpty else { return false }
            return switch filter {
            case .all: true
            case .upcoming: item.airDate >= todayKey
            case .recent: item.airDate < todayKey
            case .series: item.mediaType == "series"
            case .movies: item.mediaType == "movie"
            }
        }
        // JavaScript's sort is stable; the offset keeps ties in the server's order here too.
        let sorted = kept.sorted { lhs, rhs in
            let a = lhs.element, b = rhs.element
            if a.airDate != b.airDate { return a.airDate < b.airDate }
            let at = a.airTime ?? "99:99", bt = b.airTime ?? "99:99"
            if at != bt { return at < bt }
            return lhs.offset < rhs.offset
        }
        var days: [CalendarDay] = []
        for (_, item) in sorted {
            if let last = days.last, last.key == item.airDate {
                days[days.count - 1] = CalendarDay(key: last.key, items: last.items + [item])
            } else {
                days.append(CalendarDay(key: item.airDate, items: [item]))
            }
        }
        return days
    }

    /// Keeps the chosen release while it is still listed; else the chosen day's first
    /// release; else the first release of the first day from today on (the last day when
    /// everything is past) (`resolveCalendarSelection`).
    static func resolveSelection(_ days: [CalendarDay], dateKey: String?, itemKey: String?,
                                 todayKey: String) -> CalendarSelection {
        if let day = days.first(where: { $0.key == dateKey }) {
            if let item = day.items.first(where: { self.itemKey($0) == itemKey }) {
                return CalendarSelection(dateKey: day.key, itemKey: self.itemKey(item))
            }
            guard let first = day.items.first else { return CalendarSelection() }
            return CalendarSelection(dateKey: day.key, itemKey: self.itemKey(first))
        }
        guard let day = days.first(where: { $0.key >= todayKey }) ?? days.last, let first = day.items.first else {
            return CalendarSelection()
        }
        return CalendarSelection(dateKey: day.key, itemKey: self.itemKey(first))
    }

    // MARK: Dates

    private static var gregorian: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        return calendar
    }

    /// `YYYY-MM-DD` in the viewer's time zone (`toDateKey`).
    static func dateKey(_ date: Date) -> String {
        let parts = gregorian.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 1, parts.day ?? 1)
    }

    /// Local midnight of a `YYYY-MM-DD` key; bad parts fall back to January / the 1st.
    static func date(fromKey key: String) -> Date {
        let parts = key.split(separator: "-").map { Int($0) }
        var components = DateComponents()
        components.year = parts.first.flatMap { $0 } ?? 1970
        components.month = parts.count > 1 ? parts[1] ?? 1 : 1
        components.day = parts.count > 2 ? parts[2] ?? 1 : 1
        return gregorian.date(from: components) ?? .distantPast
    }

    /// "Today", "Tomorrow", "Yesterday", else the weekday (`formatDayHeading`).
    static func dayHeading(_ key: String, now: Date = .now) -> String {
        let calendar = gregorian
        if key == dateKey(now) { return String(localized: "Today") }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), key == dateKey(tomorrow) {
            return String(localized: "Tomorrow")
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), key == dateKey(yesterday) {
            return String(localized: "Yesterday")
        }
        return date(fromKey: key).formatted(.dateTime.weekday(.wide))
    }

    /// "Monday, October 20", a day section's heading (`formatFullDayHeading`).
    static func fullDayHeading(_ key: String) -> String {
        date(fromKey: key).formatted(.dateTime.weekday(.wide).month(.wide).day())
    }

    /// "OCT 20", the timeline marker's label.
    static func markerLabel(_ key: String) -> String {
        date(fromKey: key).formatted(.dateTime.month(.abbreviated).day()).uppercased()
    }

    /// "9:00 PM" from `HH:MM`; "All day" without a time; the raw text when it won't parse
    /// (`formatTime`).
    static func formatTime(_ time: String?) -> String {
        guard let time, !time.isEmpty else { return String(localized: "All day") }
        let parts = time.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count >= 2, let hour = Int(parts[0]), let minute = Int(parts[1]),
              let date = gregorian.date(bySettingHour: hour, minute: minute, second: 0, of: .now)
        else { return time }
        return date.formatted(date: .omitted, time: .shortened)
    }

    // MARK: Text

    /// "TV" for `tv`, else the type with its first letter capitalised (`formatReleaseType`).
    static func releaseType(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased() == "tv" { return "TV" }
        return trimmed.prefix(1).uppercased() + trimmed.dropFirst()
    }

    private static func code(_ item: CalendarItem) -> String? {
        guard let season = item.seasonNumber, season != 0, let episode = item.episodeNumber, episode != 0 else {
            return nil
        }
        return String(format: "S%02dE%02d", season, episode)
    }

    /// Under a poster: "S01E04" ("Episode" without numbers); a movie's release type
    /// (`buildPosterMetadata`).
    static func posterMetadata(_ item: CalendarItem) -> String {
        if item.isMovie { return item.releaseType.map(releaseType) ?? "" }
        return code(item) ?? String(localized: "Episode")
    }

    /// "S01E04 - Title" or "Theatrical release" (`buildEpisodeLine`).
    static func episodeLine(_ item: CalendarItem) -> String {
        if item.isMovie {
            return item.releaseType.map { "\(releaseType($0)) release" } ?? String(localized: "Movie release")
        }
        let code = code(item) ?? String(localized: "Episode")
        return item.episodeTitle.map { "\(code) - \($0)" } ?? code
    }

    /// "S1 E4" in the detail panel's metadata line; series only.
    static func episodeLabel(_ item: CalendarItem) -> String? {
        guard !item.isMovie, let season = item.seasonNumber, season != 0,
              let episode = item.episodeNumber, episode != 0 else { return nil }
        return "S\(season) E\(episode)"
    }

    /// The episode's overview, the title's, the network, else a fallback (`buildItemSummary`).
    static func summary(_ item: CalendarItem) -> String {
        if let text = item.episodeOverview?.trimmed, !text.isEmpty { return text }
        if let text = item.overview?.trimmed, !text.isEmpty { return text }
        if let network = item.network, !network.isEmpty { return "Airs on \(network)." }
        if item.isMovie {
            return item.releaseType.map { "\(releaseType($0)) release." } ?? String(localized: "Movie release.")
        }
        return String(localized: "Episode details will appear when they are available.")
    }

    /// "3 releases" / "1 release".
    static func releaseCount(_ count: Int) -> String {
        count == 1 ? String(localized: "1 release") : String(localized: "\(count) releases")
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

extension CalendarItem {
    /// `CalendarModel.itemKey`, as a key path for `ForEach`.
    var calendarKey: String { CalendarModel.itemKey(self) }
}
