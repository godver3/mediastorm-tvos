#if os(iOS)
import Foundation

/// Settings › Downloads › Delete Watched: finished downloads the profile has watched are
/// removed when the Downloads list opens (with the server reachable; offline nothing changes),
/// and never while a player is up. Matched against the profile's watched keys the way
/// `TitleStateStore` matches cards.
extension DownloadManager {
    func deleteWatchedIfEnabled() async {
        guard settings.deleteWatched, !completed.isEmpty,
              PlaybackCoordinator.shared.resolving == nil else { return }
        guard let keys = try? await APIClient.shared.watchedKeys(), !keys.isEmpty else { return }
        let watched = completed.filter { Self.isWatched($0, keys: keys) }
        guard !watched.isEmpty else { return }
        DownloadSession.log.notice("deleting \(watched.count) watched download(s)")
        delete(watched.map(\.id))
    }

    nonisolated static func isWatched(_ item: DownloadItem, keys: Set<String>) -> Bool {
        if item.isMovie {
            var ids = [item.titleID]
            if let v = item.tmdbID { ids.append("tmdb:movie:\(v)") }
            if let v = item.imdbID { ids.append(v) }
            if let v = item.tvdbID { ids.append("tvdb:movie:\(v)") }
            return ids.contains { keys.contains("movie:\($0.lowercased())") }
        }
        guard let season = item.seasonNumber, let episode = item.episodeNumber else { return false }
        var seriesIDs = [item.titleID]
        if let v = item.tvdbID { seriesIDs += ["tvdb:series:\(v)", v] }
        if let v = item.tmdbID { seriesIDs += ["tmdb:tv:\(v)", v] }
        if let v = item.imdbID { seriesIDs += ["imdb:\(v)", v] }
        let suffix = String(format: ":s%02de%02d", season, episode)
        var ids = seriesIDs.map { $0 + suffix }
        if let v = item.episodeItemID { ids.append(v) }
        return ids.contains { keys.contains("episode:\($0.lowercased())") }
    }
}
#endif
