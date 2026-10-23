import Foundation

/// The Calendar screen's reads: the profile's calendar window and, for the detail panel,
/// the focused release's title metadata (as the Expo screen reads them).
extension APIClient {
    /// `GET /api/users/{id}/calendar`, as the Expo Calendar asks for it: 90 days ahead,
    /// 21 back, in the viewer's time zone, from one source or all of them.
    func calendar(source: CalendarSource) async throws -> [CalendarItem] {
        struct Response: Decodable { let items: [CalendarItem]? }
        var query = ["days": "90", "recentDays": "21", "tz": TimeZone.current.identifier]
        if source != .all { query["source"] = source.rawValue }
        let response: Response = try await send("GET", "\(profilePath)/calendar", query: query, timeout: 90)
        return response.items ?? []
    }

    /// The detail panel's metadata for a release: `/api/metadata/movies/details` or
    /// `/api/metadata/series/details` (`fetchCalendarItemEnrichment`).
    func calendarEnrichment(_ item: CalendarItem) async throws -> CalendarEnrichment {
        var query = ["titleId": item.titleID, "name": item.title, "userId": profileID]
        if let year = item.year { query["year"] = String(year) }
        if let tmdb = item.externalIds?["tmdb"] { query["tmdbId"] = tmdb }
        if let tvdb = item.externalIds?["tvdb"] { query["tvdbId"] = tvdb }
        if item.isMovie {
            if let imdb = item.externalIds?["imdb"] { query["imdbId"] = imdb }
            let movie: Title = try await send("GET", "/api/metadata/movies/details", query: query, promptOnLock: false,
                                              timeout: 30)
            return CalendarEnrichment(movie: movie)
        }
        let series: SeriesDetails = try await send("GET", "/api/metadata/series/details", query: query,
                                                   promptOnLock: false, timeout: 30)
        return CalendarEnrichment(series: series, item: item)
    }
}
