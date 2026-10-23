import SwiftUI

/// Loading the page: the details bundle, then the collection row.
extension DetailsView {
    // MARK: Loading

    /// One `/details-bundle` call: metadata plus per-episode watched / resume, up-next and
    /// the top-level resume. Also re-run after playback to refresh progress.
    func load() async {
        do {
            let bundle = try await APIClient.shared.detailsBundle(target)
            if target.isMovie {
                guard let movie = bundle.movieDetails else { throw APIError.notReady("Details unavailable") }
                title = movie
            } else {
                guard let details = bundle.seriesDetails else { throw APIError.notReady("Details unavailable") }
                title = details.title
                seasons = details.seasons
                upNext = bundle.upNextEpisode
                primaryEpisode = Self.findPrimaryEpisode(in: details.seasons, upNext: bundle.upNextEpisode)
                airedRegularEpisodes = details.seasons.filter { $0.number > 0 }.flatMap(\.episodes)
                    .filter { $0.episodeNumber > 0 && ReleaseBadge.forEpisode(airDate: $0.airedDate) == nil }
                if selectedSeason == nil { selectedSeason = primaryEpisode?.seasonNumber }
            }
            similar = Self.unique(bundle.similar ?? [])
            trailer.prepare(bundle.trailers?.primary)
            resume = bundle.resume
            serverInWatchlist = bundle.inWatchlist
            movieWatched = bundle.watched
            contentPreference = bundle.contentPreference
            watchedOverrides = [:]
            loadError = nil
            // The primary action only exists once details have loaded.
            if focus == nil { focus = .action(.primary) }
            autoplayIfRequested()
            await loadCollection()
        } catch {
            if title == nil { loadError = error.localizedDescription }
        }
    }

    /// Movies: the collection row's movies, fetched once per collection (not on every
    /// reload after playback). A failure leaves the row out.
    func loadCollection() async {
        guard let collection = title?.collection, collection.id != loadedCollectionID else { return }
        loadedCollectionID = collection.id
        collectionMovies = (try? await APIClient.shared.collectionMovies(id: collection.id)).map(Self.unique) ?? []
    }

    /// Lazy rows need unique IDs; the server's lists can repeat a title.
    static func unique(_ titles: [Title]) -> [Title] {
        var seen = Set<String>()
        return titles.filter { seen.insert($0.id).inserted }
    }
}
