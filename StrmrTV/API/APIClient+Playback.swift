import Foundation

/// Details, source search/resolve, prequeue, progress and the stream URL the player opens.
extension APIClient {
    /// Details plus per-user state (episode `itemId`/`watched`/`resume`, up-next, resume)
    /// in one call.
    /// `seasonType` asks for an episode ordering (the one just picked); without it the
    /// server applies the profile's saved one.
    func detailsBundle(_ t: DetailsTarget, seasonType: String? = nil) async throws -> DetailsBundle {
        var q = ["type": t.isMovie ? "movie" : "series", "titleId": t.titleID, "name": t.name]
        if let seasonType, !seasonType.isEmpty { q["seasonType"] = seasonType }
        if let v = t.tmdbID { q["tmdbId"] = v }
        if let v = t.imdbID { q["imdbId"] = v }
        if let v = t.tvdbID { q["tvdbId"] = v }
        if let v = t.year { q["year"] = String(v) }
        return try await send("GET", "\(profilePath)/details-bundle", query: q)
    }

    /// Manual-selection results from the backend's indexers / scrapers, annotated with
    /// debrid cache / usenet health (pending rows resolve via `sourceHealth(token:)`).
    /// `numbering` is the episode's ordering, so "S01E02" is searched for as that ordering's episode.
    func searchSources(query: String, title: DetailsTarget, numbering: EpisodeNumbering? = nil) async throws -> [SourceResult] {
        var q = ["q": query, "titleId": title.titleID, "mediaType": title.isMovie ? "movie" : "series",
                 "userId": profileID, "includeSourceHealth": "true", "limit": "50"]  // server default is 5
        if let imdb = title.imdbID { q["imdbId"] = imdb }
        if let year = title.year { q["year"] = String(year) }
        if let numbering {
            q["episodeNumberingId"] = numbering.seriesId
            if let ordering = numbering.ordering, !ordering.isEmpty { q["episodeOrdering"] = ordering }
        }
        let data = try await sendRaw("GET", "/api/indexers/search", query: q,
                                     headers: AdaptiveThroughput.shared.requestHeaders())
        let list = (try JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
        return list.enumerated().compactMap { SourceResult($1, index: $0) }
    }

    /// Long-polls the pending source-health checks of one search.
    func sourceHealth(token: String) async throws -> SourceHealthSnapshot {
        try await send("GET", "/api/indexers/source-health", query: ["token": token, "waitMs": "20000"], timeout: 30)
    }

    /// Resolves a manually chosen result to a stream path, waiting on the backend's
    /// queue when resolution is asynchronous. The server also returns its track choice
    /// for this profile and title, so manual picks get the same preference as prequeue.
    func resolveSource(_ result: SourceResult, titleID: String, startOffset: Double?) async throws -> (path: String, tracks: TrackSelection?) {
        var body: [String: Any] = [
            "result": result.raw, "profileId": profileID, "titleId": titleID,
            "clientId": Config.clientID, "includeTrackSelection": true,
        ]
        if let startOffset { body["startOffset"] = startOffset }
        let data = try await sendRaw("POST", "/api/playback/resolve", jsonObject: body, timeout: 90)
        var resolution = try decoder.decode(PlaybackResolution.self, from: data)
        let deadline = Date().addingTimeInterval(180)
        while resolution.webdavPath?.isEmpty ?? true {
            guard let queueID = resolution.queueId, queueID > 0, Date() < deadline else {
                throw APIError.notReady("Source could not be resolved")
            }
            try await Task.sleep(for: .seconds(1))
            try Task.checkCancellation()
            let poll = try await sendRaw("GET", "/api/playback/queue/\(queueID)", query: [
                "includeTrackSelection": "true", "profileId": profileID, "titleId": titleID, "clientId": Config.clientID,
            ], timeout: 60)
            resolution = try decoder.decode(PlaybackResolution.self, from: poll)
        }
        return (resolution.webdavPath!, resolution.trackSelection)
    }

    /// Intro / recap / outro ranges, merged server-side from IntroDB, SkipDB and chapter names.
    func skipSegments(_ body: [String: Any]) async throws -> [SkipSegment] {
        let data = try await sendRaw("POST", "/api/video/segments", jsonObject: body, promptOnLock: false)
        return try decoder.decode(SkipSegmentsResponse.self, from: data).segments ?? []
    }

    func startPrequeue(_ body: [String: Any]) async throws -> PrequeueStartResponse {
        try await send("POST", "/api/playback/prequeue", jsonObject: body,
                       headers: AdaptiveThroughput.shared.requestHeaders())
    }

    func prequeueStatus(_ id: String) async throws -> PrequeueStatus {
        try await send("GET", "/api/playback/prequeue/\(Self.segment(id))")
    }

    @discardableResult
    func reportProgress(_ body: [String: Any]) async -> ProgressReply? {
        guard let data = try? await sendRaw("POST", "\(profilePath)/history/progress", jsonObject: body,
                                            promptOnLock: false) else { return nil }
        return try? decoder.decode(ProgressReply.self, from: data)
    }

    /// Raw-file stream URL for the native player. transmux=0 keeps the backend from
    /// remuxing: AetherEngine demuxes MKV/MP4 itself. Auth travels in `mediaHeaders`;
    /// the profile unlock also rides in the query, like `token=` on header-less media
    /// URLs, so it survives anything that drops custom headers. `profileId` and the
    /// media metadata let the stream tracker attribute the stream on the admin dashboard.
    func streamURL(for streamPath: String, metadata: [String: String] = [:]) -> URL {
        var query = metadata.merging(["path": streamPath, "transmux": "0", "profileId": profileID]) { _, new in new }
        if let profileName, !profileName.isEmpty { query["profileName"] = profileName }
        if let unlock = profileUnlocks.token(for: profileID) { query["profileUnlock"] = unlock }
        return url("/api/video/stream", query: query)
    }

    /// Headers the engine attaches to every media fetch.
    var mediaHeaders: [String: String] {
        var h = ["X-Client-ID": Config.clientID]
        if let remoteCredential { h["X-Remote-Access-Credential"] = remoteCredential }
        if let token { h["Authorization"] = "Bearer \(token)" }
        if let unlock = profileUnlocks.token(for: profileID) { h[Self.unlockHeader] = unlock }
        return h
    }
}
