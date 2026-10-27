import Foundation

/// Everything needed to resolve, play and report progress for one movie or episode.
struct PlaybackRequest {
    struct EpisodeInfo {
        let season: Int
        let episode: Int
        let absolute: Int?
        let name: String?
        /// The server's canonical progress item ID, when the episode came from `/details-bundle`.
        let itemID: String?
        /// Episode still, for the loading art and the player's Info panel.
        var imageURL: String? = nil
        var overview: String? = nil

        var code: String { String(format: "S%02dE%02d", season, episode) }
    }

    /// Artwork for the stream-start loading screen, from the loaded details.
    struct Artwork {
        /// Backdrops to rotate through while the stream starts, in display order.
        var backdropURLs: [String] = []
        var logoURL: String?

        /// The title's backdrops, de-duplicated and shuffled with a per-page seed (as the
        /// Expo app's preroll artwork does), with the one already on screen moved last so the
        /// loading screen opens on something new when there is a choice. An episode still,
        /// when there is one, leads.
        static func rotation(still: String?, primary: String?, alternates: [String],
                             showing: String?, seed: UInt64) -> [String] {
            func key(_ url: String) -> String {
                let path = url.split(separator: "?", maxSplits: 1).first.map(String.init) ?? url
                return path.replacingOccurrences(of: #"/(original|w\d+)/"#, with: "/", options: .regularExpression)
            }
            var seen = Set<String>()
            let unique = (alternates + [primary].compactMap { $0 }).filter { !$0.isEmpty && seen.insert(key($0)).inserted }
            var shuffled = unique.sorted { hash($0, seed) < hash($1, seed) }
            if shuffled.count > 1, let showing, let i = shuffled.firstIndex(where: { key($0) == key(showing) }) {
                shuffled.append(shuffled.remove(at: i))
            }
            if let still, !still.isEmpty { return [still] + shuffled.filter { key($0) != key(still) } }
            return shuffled
        }

        /// FNV-1a over the URL, mixed with the seed.
        private static func hash(_ value: String, _ seed: UInt64) -> UInt64 {
            var h: UInt64 = 0xcbf2_9ce4_8422_2325 ^ seed
            for byte in value.utf8 { h = (h ^ UInt64(byte)) &* 0x100_0000_01b3 }
            return h
        }
    }

    let title: DetailsTarget
    let episode: EpisodeInfo?
    /// Resume point; nil plays from the start.
    let start: StartPoint?
    /// Aired episodes after this one, in order; the first is offered at the end credits.
    var following: [EpisodeInfo] = []
    var artwork = Artwork()
    /// The title's copies in the profile's libraries: Play and Up Next play a movie's or an
    /// episode's copy when it has one, without the prequeue.
    var library: LibraryVersions?
    /// The copy this playback uses (picked in the Versions list, or set as it starts).
    var libraryVersion: LibraryVersion?

    #if DEBUG
    /// `SoftwarePlayerProbe` plays a local file under a made-up title; it must not reach watch history.
    var reportsProgress = true
    #endif

    var isEpisode: Bool { episode != nil }

    /// The copy to play: the one picked, else this movie's or episode's best.
    var preferredLibraryVersion: LibraryVersion? {
        libraryVersion ?? library?.best(season: episode?.season, episode: episode?.episode)
    }

    /// An unmatched library file (a home video): its progress is keyed by its stream path, as
    /// in the Expo app, since no catalog id names it.
    var isUnmatchedLibraryFile: Bool { libraryVersion != nil && !title.hasCatalogIDs }
    var progressMediaType: String { isEpisode ? "episode" : "movie" }

    /// Exact start position in seconds (a percentage resume is applied once the duration is known).
    var startPosition: Double? {
        if case let .seconds(s) = start { return s }
        return nil
    }

    /// Movies report under their title ID; episodes use the server's `itemId` verbatim, or
    /// nil so the server derives it from series + season + episode.
    var progressItemID: String? {
        guard let episode else { return title.titleID }
        return episode.itemID
    }

    /// What the server's stream tracker reads off `/api/video/stream` (`parseStreamMediaMetadata`)
    /// to put this playback on the admin dashboard and match it to its progress heartbeats.
    /// Episodes without a server itemId send `{series}:SxxEyy`, as the Expo app does.
    var streamMetadataQuery: [String: String] {
        let t = title
        var q = ["mediaType": progressMediaType, "titleId": t.titleID]
        if let v = t.tmdbID { q["tmdb"] = v }
        if let v = t.imdbID { q["imdb"] = v }
        if let v = t.tvdbID { q["tvdb"] = v }
        if let y = t.year { q["year"] = String(y) }
        // Absolute art only: a library poster's server path means nothing in a notification.
        if let poster = t.posterURL, poster.hasPrefix("http") { q["posterUrl"] = poster }
        if let episode {
            q["itemId"] = episode.itemID ?? "\(t.titleID):\(episode.code)"
            q["seriesId"] = t.titleID
            q["seriesName"] = t.name
            q["title"] = t.name
            q["seasonNumber"] = String(episode.season)
            q["episodeNumber"] = String(episode.episode)
            if let name = episode.name, !name.isEmpty { q["episodeName"] = name }
        } else {
            q["itemId"] = t.titleID
            q["movieName"] = t.name
            q["title"] = t.name
        }
        return q
    }

    /// `streamMetadataQuery` for the stream at `path`: an unmatched library file goes by its path.
    func streamMetadata(path: String) -> [String: String] {
        var q = streamMetadataQuery
        if isUnmatchedLibraryFile {
            q["itemId"] = path
            q["seriesId"] = nil
            q["titleId"] = nil
        }
        return q
    }

    /// The next episode from the start, if there is one. Its loading art leads with its own
    /// still in place of this episode's. It plays its own library copy, if it has one.
    var nextEpisode: PlaybackRequest? {
        guard let next = following.first else { return nil }
        var art = artwork
        art.backdropURLs.removeAll { $0 == episode?.imageURL }
        if let still = next.imageURL, !still.isEmpty { art.backdropURLs.insert(still, at: 0) }
        return PlaybackRequest(title: title, episode: next, start: nil, following: Array(following.dropFirst()),
                               artwork: art, library: library)
    }

    /// Identifies what a prequeue resolves: the title, the episode and the start point.
    var prequeueKey: String {
        [title.titleID, episode?.code ?? "", startPosition.map { String(Int($0)) } ?? ""].joined(separator: "|")
    }

    var displayTitle: String {
        guard let episode else { return title.name }
        return "\(title.name) · \(episode.code)"
    }

    var displaySubtitle: String? { episode?.name }

    /// The Info panel's description: the episode's overview, else the title's.
    var infoDescription: String? {
        if let overview = episode?.overview, !overview.isEmpty { return overview }
        return title.overview
    }

    /// The Info panel's 16:9 image: the episode still, else the title's backdrop (the loading
    /// art's first that isn't a still), else the poster.
    var infoArtworkURL: URL? {
        let still = episode?.imageURL.flatMap { $0.isEmpty ? nil : $0 }
        let backdrop = title.backdropURL.flatMap { $0.isEmpty ? nil : $0 }
            ?? artwork.backdropURLs.first { $0 != episode?.imageURL }
        return sizedArtworkURL(still ?? backdrop ?? title.posterURL, size: "w780")
    }

    /// The `/api/progress` body for a position in this playback. A library file names its
    /// `sourcePath`, which is how the server knows to report the playback to Plex or Jellyfin.
    func progressReport(position: Double, duration: Double, paused: Bool, ended: Bool,
                        sourcePath: String? = nil) -> [String: Any] {
        let t = title
        var body: [String: Any] = [
            "mediaType": progressMediaType,
            "position": position,
            "duration": duration,
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "isPaused": paused,
            "playbackEnded": ended,
        ]
        if libraryVersion != nil, let sourcePath { body["sourcePath"] = sourcePath }
        if isUnmatchedLibraryFile, let sourcePath {
            // Keyed by the stream path, with no catalog ids (the Expo app's rule).
            body["itemId"] = sourcePath
            if let ep = episode {
                body["seasonNumber"] = ep.season
                body["episodeNumber"] = ep.episode
                body["seriesName"] = t.name
                if let name = ep.name { body["episodeName"] = name }
            } else {
                body["movieName"] = t.name
            }
            return body
        }
        var ids: [String: String] = ["titleId": t.titleID]
        if let v = t.tmdbID { ids["tmdb"] = v }
        if let v = t.imdbID { ids["imdb"] = v }
        if let v = t.tvdbID { ids["tvdb"] = v }
        body["externalIds"] = ids
        // Episodes without a server itemId: the server derives it from seriesId + season + episode.
        if let itemID = progressItemID { body["itemId"] = itemID }
        if let y = t.year { body["year"] = y }
        if let ep = episode {
            body["seasonNumber"] = ep.season
            body["episodeNumber"] = ep.episode
            body["seriesId"] = t.titleID
            body["seriesName"] = t.name
            if let name = ep.name { body["episodeName"] = name }
        } else {
            body["movieName"] = t.name
        }
        if let poster = t.posterURL, poster.hasPrefix("http") { body["posterUrl"] = poster }
        return body
    }
}

/// The global `Artwork.url`, which `PlaybackRequest.Artwork` shadows inside the struct.
private func sizedArtworkURL(_ raw: String?, size: String) -> URL? {
    Artwork.url(raw, size: size)
}
