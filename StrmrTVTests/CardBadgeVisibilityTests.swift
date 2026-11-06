import XCTest
@testable import StrmrTV

/// Settings › Card Badges: this device's choice, else the profile's `badgeVisibility`, else
/// the server default (`watchProgress` only); and when the unwatched count shows.
final class CardBadgeVisibilityTests: XCTestCase {
    private let all = BadgeVisibility(watchState: true, releaseStatus: true, unwatchedCount: true)

    func testServerDefaultShowsNone() {
        XCTAssertEqual(BadgeVisibility.resolve(device: [:], server: nil), BadgeVisibility())
        XCTAssertEqual(BadgeVisibility.resolve(device: [:], server: ["watchProgress"]), BadgeVisibility())
    }

    func testProfileListIsFollowed() {
        let v = BadgeVisibility.resolve(device: [:], server: ["watchProgress", "unwatchedCount", " WatchState "])
        XCTAssertEqual(v, BadgeVisibility(watchState: true, releaseStatus: false, unwatchedCount: true))
    }

    func testDeviceOverridesProfile() {
        let v = BadgeVisibility.resolve(device: [.watchState: false, .releaseStatus: true],
                                        server: ["watchState", "unwatchedCount"])
        XCTAssertEqual(v, BadgeVisibility(watchState: false, releaseStatus: true, unwatchedCount: true))
        XCTAssertEqual(BadgeVisibility.resolve(device: [.unwatchedCount: true], server: nil),
                       BadgeVisibility(watchState: false, releaseStatus: false, unwatchedCount: true))
    }

    func testCountShowsInsideWatchBadge() {
        var counted = CardBadge.inProgress
        counted.count = 5
        XCTAssertEqual(all.badges(badge: nil, watch: .inProgress, unwatchedCount: 5), [counted])
    }

    func testCountAloneWithoutWatchState() {
        let off = BadgeVisibility(watchState: false, releaseStatus: false, unwatchedCount: true)
        let badges = off.badges(badge: nil, watch: .inProgress, unwatchedCount: 3)
        XCTAssertEqual(badges.map(\.count), [3])
        XCTAssertNil(badges.first?.symbol)
        XCTAssertEqual(badges.first?.accessibilityText, "3 unwatched episodes")
    }

    func testZeroCountShowsMissingOrOffHides() {
        var zero = CardBadge.watched
        zero.count = 0
        XCTAssertEqual(all.badges(badge: nil, watch: .watched, unwatchedCount: 0), [zero])
        XCTAssertEqual(all.badges(badge: nil, watch: nil, unwatchedCount: nil), [])
        let noCount = BadgeVisibility(watchState: true, releaseStatus: false, unwatchedCount: false)
        XCTAssertEqual(noCount.badges(badge: nil, watch: .inProgress, unwatchedCount: 4), [.inProgress])
    }

    func testContinueWatchingSeriesWatch() {
        XCTAssertTrue(HomeCard.seriesWatch(total: 10, watched: 3, started: false) == (.inProgress, 7))
        XCTAssertTrue(HomeCard.seriesWatch(total: 10, watched: 10, started: false) == (.watched, 0))
        XCTAssertTrue(HomeCard.seriesWatch(total: 10, watched: 12, started: false) == (.watched, 0))
        XCTAssertTrue(HomeCard.seriesWatch(total: nil, watched: nil, started: true) == (.inProgress, nil))
        XCTAssertTrue(HomeCard.seriesWatch(total: 8, watched: 0, started: false) == (nil, 8))
    }

    func testReleaseStatusGatedButRankAndAirDateAlwaysShow() {
        let none = BadgeVisibility()
        XCTAssertEqual(none.badges(badge: .comingSoon, watch: .watched, unwatchedCount: nil), [])
        XCTAssertEqual(none.badges(badge: CardBadge(text: "#2"), watch: nil, unwatchedCount: nil), [CardBadge(text: "#2")])
        XCTAssertEqual(none.badges(badge: CardBadge(text: "Airs Tomorrow"), watch: nil, unwatchedCount: nil).count, 1)
        XCTAssertEqual(all.badges(badge: .comingSoon, watch: .watched, unwatchedCount: nil), [.comingSoon, .watched])
    }

    @MainActor
    func testCardsCarrySeriesCountsOnly() throws {
        func decode(_ json: [String: Any]) throws -> Title {
            try JSONDecoder().decode(Title.self, from: JSONSerialization.data(withJSONObject: json))
        }
        let series = try decode(["id": "tmdb:tv:1", "name": "Show", "mediaType": "series", "unwatchedCount": 7])
        let movie = try decode(["id": "tmdb:movie:1", "name": "Film", "mediaType": "movie", "unwatchedCount": 7])
        XCTAssertEqual(PosterCard(title: series).unwatchedCount, 7)
        XCTAssertEqual(HomeCard(series).unwatchedCount, 7)
        XCTAssertNil(PosterCard(title: movie).unwatchedCount)
    }
}
