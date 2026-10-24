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
        let updates = episodes.map {
            Self.episodeUpdate(series, watched: watched, itemID: $0.itemId, name: $0.name,
                               season: $0.seasonNumber, episode: $0.episodeNumber)
        }
        try await sendRaw("POST", "/api/users/\(Self.segment(profileID))/history/watched/bulk",
                          query: scope.map { ["scope": $0.rawValue] } ?? [:],
                          jsonArray: updates)
    }

    /// One card's episode (Continue Watching, the calendar), from a long press.
    func setWatched(_ watched: Bool, episode: CardEpisode, of series: DetailsTarget) async throws {
        let update = Self.episodeUpdate(series, watched: watched, itemID: episode.itemId, name: episode.name,
                                        season: episode.seasonNumber, episode: episode.episodeNumber)
        try await sendRaw("POST", "/api/users/\(Self.segment(profileID))/history/watched/bulk",
                          jsonArray: [update])
    }

    private static func episodeUpdate(_ series: DetailsTarget, watched: Bool, itemID: String?, name: String?,
                                      season: Int, episode: Int) -> [String: Any] {
        var update = watchedBase(series, watched: watched)
        update["mediaType"] = "episode"
        // Without an itemId the server derives it from series + season + episode.
        if let itemID { update["itemId"] = itemID }
        if let name { update["name"] = name }
        update["seriesId"] = series.titleID
        update["seriesName"] = series.name
        update["seasonNumber"] = season
        update["episodeNumber"] = episode
        return update
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
