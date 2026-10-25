import XCTest
@testable import StrmrTV

/// The details page's episode air dates (the Expo strip's `formatAirDate`).
final class EpisodeAirDateTests: XCTestCase {
    func testFormatsLikeExpo() {
        XCTAssertEqual(EpisodeCard.airDateText("2026-10-21"), "Oct 21, 2026")
        XCTAssertEqual(EpisodeCard.airDateText("2022-05-20T00:00:00Z"), "May 20, 2022")
        XCTAssertNil(EpisodeCard.airDateText(nil))
        XCTAssertNil(EpisodeCard.airDateText("TBA"))
    }

    /// Episode card and details header runtimes.
    func testFormatsRuntime() {
        XCTAssertEqual(formatRuntime(49), "49m")
        XCTAssertEqual(formatRuntime(60), "1h")
        XCTAssertEqual(formatRuntime(65), "1h 5m")
        XCTAssertNil(formatRuntime(0))
        XCTAssertNil(formatRuntime(nil))
    }
}
