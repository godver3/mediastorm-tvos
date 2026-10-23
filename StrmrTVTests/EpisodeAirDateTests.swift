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
}
