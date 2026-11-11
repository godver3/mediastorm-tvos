import XCTest
@testable import StrmrTV

/// Bulk watched changes ask first: every whole-show choice, a season from 50 episodes.
final class BulkWatchChangeTests: XCTestCase {
    func testWholeShowAlwaysAsks() {
        XCTAssertTrue(BulkWatchChange.needsConfirmation(.wholeShow, count: 1))
        XCTAssertTrue(BulkWatchChange.needsConfirmation(.wholeShowExcept(season: 67), count: 3))
    }

    func testSeasonAsksFromThreshold() {
        XCTAssertFalse(BulkWatchChange.needsConfirmation(.season("Season 1"), count: 49))
        XCTAssertTrue(BulkWatchChange.needsConfirmation(.season("Season 67"), count: 50))
    }

    func testCopyNamesCountAndShow() {
        let change = BulkWatchChange(watched: true, count: 11247, seriesName: "Coronation Street",
                                     extent: .wholeShowExcept(season: 67)) {}
        XCTAssertTrue(change.title.hasPrefix("Mark 11"), change.title)
        XCTAssertTrue(change.title.hasSuffix("episodes watched?"), change.title)
        XCTAssertTrue(change.message.contains("Coronation Street except Season 67"), change.message)
        XCTAssertTrue(change.message.contains("haven't played won't appear in watch history"), change.message)
        XCTAssertEqual(change.confirmLabel, "Mark Watched")

        let unwatch = BulkWatchChange(watched: false, count: 1, seriesName: "Show", extent: .wholeShow) {}
        XCTAssertEqual(unwatch.title, "Mark 1 episode unwatched?")
        XCTAssertTrue(unwatch.message.contains("clearing their watched state"), unwatch.message)
    }
}
