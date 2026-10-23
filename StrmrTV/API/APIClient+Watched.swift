import Foundation

/// Bulk scope for `history/watched/bulk`: tells Trakt-style providers a whole show or one
/// season changed, so they can use their own bulk calls.
enum WatchedScope: String {
    case show, season
}

extension APIClient {
    /// Marks a movie or episodes watched / unwatched in one `POST /history/watched/bulk`.
    /// The server matches existing rows across ID forms, so items carry the server's
    /// `itemId` (episodes from `/details-bundle`) plus the title's external IDs.
    func setWatched(_ watched: Bool, movie title: DetailsTarget) async throws {
        var update = Self.watchedBase(title, watched: watched)
        update["mediaType"] = "movie"
        update["itemId"] = title.titleID
        if let year = title.year { update["year"] = year }
        try await sendRaw("POST", "/api/users/\(Self.segment(profileID))/history/watched/bulk",
                          jsonArray: [update])
    }

    func setWatched(_ watched: Bool, episodes: [Episode], of series: DetailsTarget,
                    scope: WatchedScope? = nil) async throws {
        guard !episodes.isEmpty else { return }
        let updates = episodes.map { ep -> [String: Any] in
            var update = Self.watchedBase(series, watched: watched)
            update["mediaType"] = "episode"
            // Without an itemId the server derives it from series + season + episode.
            if let itemID = ep.itemId { update["itemId"] = itemID }
            update["name"] = ep.name
            update["seriesId"] = series.titleID
            update["seriesName"] = series.name
            update["seasonNumber"] = ep.seasonNumber
            update["episodeNumber"] = ep.episodeNumber
            return update
        }
        try await sendRaw("POST", "/api/users/\(Self.segment(profileID))/history/watched/bulk",
                          query: scope.map { ["scope": $0.rawValue] } ?? [:],
                          jsonArray: updates)
    }

    private static func watchedBase(_ title: DetailsTarget, watched: Bool) -> [String: Any] {
        var ids: [String: String] = [:]
        if let v = title.tmdbID { ids["tmdb"] = v }
        if let v = title.imdbID { ids["imdb"] = v }
        if let v = title.tvdbID { ids["tvdb"] = v }
        var update: [String: Any] = ["watched": watched, "name": title.name]
        if !ids.isEmpty { update["externalIds"] = ids }
        return update
    }
}
