#if os(iOS)
import Foundation

/// The download picker's searches and resolves: the indexer search ranked for downloading
/// (`downloadRanking`, which favours smaller, widely compatible files), season packs only for
/// Download Season, and the batch resolve that picks each episode's file from one pack.
extension APIClient {
    func downloadSources(query: String, title: DetailsTarget, numbering: EpisodeNumbering?,
                         seasonPacksOnly: Bool) async throws -> [SourceResult] {
        var q = ["q": query, "titleId": title.titleID, "mediaType": title.isMovie ? "movie" : "series",
                 "userId": profileID, "includeSourceHealth": "true", "limit": "50", "downloadRanking": "true"]
        if let imdb = title.imdbID { q["imdbId"] = imdb }
        if let year = title.year { q["year"] = String(year) }
        if seasonPacksOnly { q["seasonPacks"] = "true" }
        if let numbering {
            q["episodeNumberingId"] = numbering.seriesId
            if let ordering = numbering.ordering, !ordering.isEmpty { q["episodeOrdering"] = ordering }
        }
        let data = try await sendRaw("GET", "/api/indexers/search", query: q, timeout: 90,
                                     headers: AdaptiveThroughput.shared.requestHeaders())
        let list = (try JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
        return list.enumerated().compactMap { SourceResult($1, index: $0) }
    }

    struct BatchResolution: Decodable {
        struct Resolution: Decodable {
            let webdavPath: String?
            let fileSize: Int64?
        }

        let seasonNumber: Int
        let episodeNumber: Int
        let resolution: Resolution?
        let error: String?
    }

    /// Resolves one season pack for several episodes in one round trip.
    func resolveBatch(_ result: SourceResult, episodes: [Episode]) async throws -> [BatchResolution] {
        struct Response: Decodable { let results: [BatchResolution]? }
        let targets: [[String: Any]] = episodes.map { ep in
            var t: [String: Any] = ["seasonNumber": ep.seasonNumber, "episodeNumber": ep.episodeNumber,
                                    "episodeCode": ep.code]
            if let absolute = ep.absoluteEpisodeNumber { t["absoluteEpisodeNumber"] = absolute }
            if let aired = ep.airedDate { t["airDate"] = aired }
            return t
        }
        // A usenet pack is imported before episodes are picked, which can take minutes.
        let timeout: TimeInterval = result.serviceType.lowercased() == "debrid" ? 120 : 900
        let data = try await sendRaw("POST", "/api/playback/resolve-batch",
                                     jsonObject: ["result": result.raw, "episodes": targets], timeout: timeout)
        return try decoder.decode(Response.self, from: data).results ?? []
    }
}
#endif
