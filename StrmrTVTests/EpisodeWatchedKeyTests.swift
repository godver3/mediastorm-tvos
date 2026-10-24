import XCTest
@testable import StrmrTV

/// A card's single episode reads its watched state from the server's watched keys
/// (`history/watched?format=keys`): `episode:` plus any series ID form and `:sXXeYY`, or the
/// episode's own item ID (mediaidentity.CandidateIDs for episodes).
@MainActor
final class EpisodeWatchedKeyTests: XCTestCase {
    private let series = DetailsTarget(titleID: "tmdb:tv:1396", name: "Breaking Bad", isMovie: false, year: 2008,
                                       tmdbID: "1396", imdbID: "tt0903747", tvdbID: "81189", posterURL: nil,
                                       textPosterURL: nil, backdropURL: nil, logoURL: nil, overview: nil)
    private let episode = CardEpisode(seasonNumber: 2, episodeNumber: 5, name: "Breakage", itemId: nil)

    private func store(_ keys: Set<String>) -> TitleStateStore {
        let store = TitleStateStore()
        store.watchedKeys = keys
        return store
    }

    func testMatchesAnySeriesIDForm() {
        XCTAssertTrue(store(["episode:tmdb:tv:1396:s02e05"]).isWatched(episode, of: series))
        XCTAssertTrue(store(["episode:tvdb:series:81189:s02e05"]).isWatched(episode, of: series), "Trakt-style tvdb import")
        XCTAssertTrue(store(["episode:81189:s02e05"]).isWatched(episode, of: series), "bare tvdb ID")
        XCTAssertTrue(store(["episode:tt0903747:s02e05"]).isWatched(episode, of: series), "bare IMDb ID")
    }

    func testOtherEpisodesAndMoviesDoNotMatch() {
        XCTAssertFalse(store(["episode:tmdb:tv:1396:s02e04", "episode:tmdb:tv:1396:s12e05"]).isWatched(episode, of: series))
        XCTAssertFalse(store(["movie:tmdb:tv:1396:s02e05"]).isWatched(episode, of: series))
        XCTAssertFalse(store([]).isWatched(episode, of: series))
    }

    func testMatchesItemIDCaseInsensitively() {
        let ep = CardEpisode(seasonNumber: 2, episodeNumber: 5, name: nil, itemId: "Plex:12345")
        XCTAssertTrue(store(["episode:plex:12345"]).isWatched(ep, of: series))
    }
}
