import XCTest
@testable import StrmrTV

/// The details ratings line: decoding from the bundle, Expo's order and score formats.
final class RatingStyleTests: XCTestCase {
    func testDecodesFromTitle() throws {
        let json = """
        {"id": "tmdb:movie:603", "name": "The Matrix", "mediaType": "movie",
         "ratings": [{"source": "imdb", "value": 8.7, "max": 10}, {"source": "tomatoes", "value": 83, "max": 100}]}
        """
        let title = try JSONDecoder().decode(Title.self, from: Data(json.utf8))
        XCTAssertEqual(title.ratings?.map(\.source), ["imdb", "tomatoes"])
    }

    func testExpoOrderWithUnknownSourcesLast() {
        let ratings = ["letterboxd", "custom", "tomatoes", "imdb"].map { Rating(source: $0, value: 1, max: 10) }
        XCTAssertEqual(RatingStyle.sorted(ratings).map(\.source), ["imdb", "tomatoes", "letterboxd", "custom"])
    }

    func testFormats() {
        XCTAssertEqual(RatingStyle(Rating(source: "imdb", value: 8.66, max: 10)).text, "8.7")
        XCTAssertEqual(RatingStyle(Rating(source: "letterboxd", value: 3.5, max: 5)).text, "3.5")
        XCTAssertEqual(RatingStyle(Rating(source: "metacritic", value: 72.6, max: 100)).text, "73%")
        XCTAssertEqual(RatingStyle(Rating(source: "other", value: 6.26, max: 10)).text, "6.3")
        XCTAssertEqual(RatingStyle(Rating(source: "other", value: 64, max: 100)).text, "64%")
    }

    func testRottenTomatoesFreshAtSixty() {
        XCTAssertEqual(RatingStyle(Rating(source: "tomatoes", value: 60, max: 100)).icon, "rt_critics.png")
        XCTAssertEqual(RatingStyle(Rating(source: "tomatoes", value: 59, max: 100)).icon, "rt_rotten.png")
        XCTAssertEqual(RatingStyle(Rating(source: "tomatoes", value: 7, max: 10)).icon, "rt_critics.png")
    }
}
