import XCTest
@testable import StrmrTV

final class LiveTimeshiftTests: XCTestCase {
    func testStatusTextAtLiveAndBehind() {
        XCTAssertEqual(LiveTimeshiftStatusView.text(paused: true, behindSeconds: 3), "Paused")
        XCTAssertEqual(LiveTimeshiftStatusView.text(paused: false, behindSeconds: 133), "2:13 behind live · ↑ Live")
        XCTAssertEqual(LiveTimeshiftStatusView.text(paused: true, behindSeconds: 133), "Paused · 2:13 behind live · ↑ Live")
        XCTAssertEqual(LiveTimeshiftStatusView.text(paused: false, behindSeconds: 0), "")
    }

    func testClockFormat() {
        XCTAssertEqual(LiveTimeshiftStatusView.clock(0), "0:00")
        XCTAssertEqual(LiveTimeshiftStatusView.clock(59.6), "1:00")
        XCTAssertEqual(LiveTimeshiftStatusView.clock(3733), "1:02:13")
    }
}
