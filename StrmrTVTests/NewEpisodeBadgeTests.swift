import XCTest
@testable import StrmrTV

/// The Expo "New" badge rule (`hasRecentlyAiredNextEpisode` / `getRecentEpisodeBadge` in
/// features/home/watch-state-cards.ts): aired, and no more than 72 hours ago.
final class NewEpisodeBadgeTests: XCTestCase {
    private let now = try! Date("2026-10-21T12:00:00Z", strategy: .iso8601)

    private func badge(_ airDate: String? = nil, utc: String? = nil, status: String? = nil) -> NewEpisodeBadge? {
        NewEpisodeBadge(airDate: airDate, airDateTimeUTC: utc, prequeueStatus: status, now: now)
    }

    func testExactAirTimeWithinWindow() {
        XCTAssertNotNil(badge(utc: "2026-10-21T02:00:00Z"))
        XCTAssertNotNil(badge(utc: "2026-10-18T12:00:00Z"), "exactly 72 hours ago still counts")
    }

    func testOutsideWindowOrNotAired() {
        XCTAssertNil(badge(utc: "2026-10-18T11:59:59Z"), "just over 72 hours")
        XCTAssertNil(badge(utc: "2026-10-21T12:00:01Z"), "not out yet")
        XCTAssertNil(badge(), "no air date")
        XCTAssertNil(badge("garbage"))
    }

    func testExactTimeWinsOverAirDay() {
        XCTAssertNil(badge("2026-10-20", utc: "2026-10-22T01:00:00Z"))
    }

    func testAirDayCountsFromLocalMidnight() {
        let calendar = Calendar.current
        let day = { (offset: Int) in
            let date = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: .now))!
            return date.formatted(.iso8601.year().month().day())
        }
        XCTAssertNotNil(NewEpisodeBadge(airDate: day(0), airDateTimeUTC: nil, prequeueStatus: nil))
        XCTAssertNotNil(NewEpisodeBadge(airDate: day(-2), airDateTimeUTC: nil, prequeueStatus: nil))
        XCTAssertNil(NewEpisodeBadge(airDate: day(-4), airDateTimeUTC: nil, prequeueStatus: nil))
        XCTAssertNil(NewEpisodeBadge(airDate: day(1), airDateTimeUTC: nil, prequeueStatus: nil))
    }

    func testReadyColourFollowsPrequeue() {
        XCTAssertEqual(badge(utc: "2026-10-21T02:00:00Z", status: "ready")?.ready, true)
        XCTAssertEqual(badge(utc: "2026-10-21T02:00:00Z", status: "queued")?.ready, false)
        XCTAssertEqual(badge(utc: "2026-10-21T02:00:00Z")?.ready, false)
    }
}
