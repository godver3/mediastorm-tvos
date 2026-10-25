import XCTest
@testable import StrmrTV

/// Title cards (Search, list rows) mark the server's `watchState`, after the rank and release badges.
@MainActor
final class WatchStateBadgeTests: XCTestCase {
    private func title(availability: String = "released", watchState: String?) throws -> Title {
        var json: [String: Any] = ["id": "tmdb:movie:1", "name": "Seen", "mediaType": "movie", "availability": availability]
        if let watchState { json["watchState"] = watchState }
        return try JSONDecoder().decode(Title.self, from: JSONSerialization.data(withJSONObject: json))
    }

    func testWatchStateMapsToBadge() {
        XCTAssertEqual(CardBadge.forWatchState("complete"), .watched)
        XCTAssertEqual(CardBadge.forWatchState("partial"), .inProgress)
        XCTAssertNil(CardBadge.forWatchState("none"))
        XCTAssertNil(CardBadge.forWatchState(nil))
    }

    func testSearchCardsShowWatchState() throws {
        XCTAssertEqual(PosterCard(title: try title(watchState: "complete")).badge, .watched)
        XCTAssertEqual(HomeCard(try title(watchState: "partial")).badge, .inProgress)
        XCTAssertNil(PosterCard(title: try title(watchState: nil)).badge)
    }

    func testRankAndReleaseBadgesWin() throws {
        XCTAssertEqual(PosterCard(title: try title(availability: "coming_soon", watchState: "complete")).badge, .comingSoon)
        XCTAssertEqual(PosterCard(title: try title(watchState: "complete"), rank: 2).badge, CardBadge(text: "#2"))
    }
}
