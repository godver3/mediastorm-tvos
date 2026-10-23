import XCTest
@testable import StrmrTV

/// Home list decoding: Go encodes an empty slice as `null` (Pat's Continue Watching once
/// its only in-progress title was hidden), and one malformed item must not cost the row.
final class LossyArrayTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    func testNullBodyIsAnEmptyList() throws {
        XCTAssertTrue(try decode(LossyArray<ContinueWatchingItem>.self, "null").elements.isEmpty)
        XCTAssertTrue(try decode(LossyArray<ContinueWatchingItem>.self, "[]").elements.isEmpty)
        // The strict decode this replaces failed the whole row ("data is missing").
        XCTAssertThrowsError(try decode([ContinueWatchingItem].self, "null"))
    }

    func testSkipsTheBadItemAndKeepsTheRest() throws {
        let json = """
        [
          {"seriesId": "tmdb:movie:603", "seriesTitle": "The Matrix", "percentWatched": 41,
           "resume": {"position": 2800, "duration": 8160, "percent": 34.3, "eligible": true}},
          {"seriesId": "tmdb:tv:105248", "externalIds": {"tmdb": "105248"},
           "lastWatched": {"seasonNumber": 0, "episodeNumber": 0}},
          {"seriesId": "tmdb:tv:105248", "seriesTitle": "Cyberpunk: Edgerunners",
           "nextEpisode": {"seasonNumber": 1, "episodeNumber": 2, "itemId": "tmdb:tv:105248:s01e02"},
           "resume": {"position": 0, "duration": 0, "percent": 0}},
          {"seriesId": "tmdb:tv:206586", "seriesTitle": "The Terminal List",
           "nextEpisode": {"seasonNumber": 1, "episodeNumber": 1}}
        ]
        """
        let items = try decode(LossyArray<ContinueWatchingItem>.self, json).elements
        // The title-less marker and the item whose `resume` lacks `eligible` are skipped.
        XCTAssertEqual(items.map(\.seriesTitle), ["The Matrix", "The Terminal List"])
        XCTAssertEqual(items.last?.nextEpisode?.code, "S01E01")
    }

    func testDisplayListPageToleratesNullAndBadItems() throws {
        let page = try decode(DisplayListPage<WatchlistItem>.self, #"{"items": null, "total": 0}"#)
        XCTAssertTrue(page.items.isEmpty)
        let mixed = try decode(DisplayListPage<WatchlistItem>.self, """
        {"items": [{"id": "tmdb:movie:1", "mediaType": "movie", "name": "One"}, {"id": "broken"}], "total": 2}
        """)
        XCTAssertEqual(mixed.items.map(\.id), ["tmdb:movie:1"])
        XCTAssertEqual(mixed.total, 2)
    }

    func testDescribesTheMissingKeyAndPath() throws {
        do {
            _ = try decode([ContinueWatchingItem].self, #"[{"seriesId": "x"}]"#)
            XCTFail("expected a decoding error")
        } catch {
            XCTAssertEqual(LossyArray<ContinueWatchingItem>.describe(error), "keyNotFound seriesTitle at [0]")
        }
    }
}
