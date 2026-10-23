import Foundation

/// The profile's watchlist, shared by the Watchlist tab, the Home row and the details
/// toggle so a change in one shows everywhere. Writes update the list optimistically,
/// then re-read the server's copy (canonical IDs, artwork, release badges).
@MainActor
final class WatchlistStore: ObservableObject {
    @Published private(set) var items: [WatchlistItem] = []
    @Published private(set) var isLoaded = false
    @Published private(set) var loadError: String?
    /// Titles toggled this session, keyed by `DetailsTarget.titleID`. A details page's
    /// `inWatchlist` comes from its bundle and goes stale after a toggle; this wins over it.
    @Published private var overrides: [String: Bool] = [:]

    private var refreshTask: Task<Void, Never>?

    /// Loads the list; concurrent callers share one request.
    func refresh() async {
        if let refreshTask { return await refreshTask.value }
        let task = Task {
            do {
                items = try await APIClient.shared.watchlist()
                loadError = nil
            } catch {
                if !isLoaded || items.isEmpty { loadError = error.localizedDescription }
            }
            isLoaded = true
        }
        refreshTask = task
        await task.value
        refreshTask = nil
    }

    /// Membership for a details page: a toggle made this session, else the server's
    /// `inWatchlist`, else (older servers) a match against the loaded list.
    func contains(_ target: DetailsTarget, server: Bool?) -> Bool {
        if let override = overrides[target.titleID] { return override }
        if let server { return server }
        return items.contains { Self.matches($0, target) }
    }

    func add(_ target: DetailsTarget) async throws {
        overrides[target.titleID] = true
        do {
            let stored = try await APIClient.shared.addToWatchlist(target.watchlistUpsert)
            if !items.contains(where: { $0.id == stored.id }) { items.insert(stored, at: 0) }
        } catch {
            overrides[target.titleID] = nil
            throw error
        }
        await refresh()
        overrides[target.titleID] = true  // keep the button steady if the re-read failed
    }

    func remove(_ target: DetailsTarget) async throws {
        overrides[target.titleID] = false
        let previous = items
        items.removeAll { Self.matches($0, target) }
        do {
            try await APIClient.shared.removeFromWatchlist(mediaType: target.isMovie ? "movie" : "series", id: target.titleID)
        } catch {
            overrides[target.titleID] = nil
            items = previous
            throw error
        }
        await refresh()
        overrides[target.titleID] = false
    }

    /// Fallback match for servers without `inWatchlist`: the same ID, or a shared
    /// provider ID of the same kind.
    nonisolated static func matches(_ item: WatchlistItem, _ target: DetailsTarget) -> Bool {
        guard item.isMovie == target.isMovie else { return false }
        if item.id == target.titleID { return true }
        let ids = item.externalIds ?? [:]
        return [("tmdb", target.tmdbID), ("imdb", target.imdbID), ("tvdb", target.tvdbID)].contains { key, value in
            guard let value, !value.isEmpty else { return false }
            return ids[key] == value
        }
    }
}

extension DetailsTarget {
    var watchlistUpsert: WatchlistUpsert {
        var ids: [String: String] = [:]
        if let tmdbID { ids["tmdb"] = tmdbID }
        if let imdbID { ids["imdb"] = imdbID }
        if let tvdbID { ids["tvdb"] = tvdbID }
        return WatchlistUpsert(id: titleID, mediaType: isMovie ? "movie" : "series", name: name,
                               overview: overview, year: year, posterUrl: posterURL, textPosterUrl: textPosterURL,
                               backdropUrl: backdropURL,
                               externalIds: ids.isEmpty ? nil : ids)
    }
}
