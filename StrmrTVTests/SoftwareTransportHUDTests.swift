import XCTest
@testable import StrmrTV

/// The software route's HUD reads time as AVKit's transport bar does.
@MainActor
final class SoftwareTransportHUDTests: XCTestCase {
    func testClockPadsMinutesUnderAnHour() {
        XCTAssertEqual(SoftwareTransportHUD.clock(4), "00:04")
        XCTAssertEqual(SoftwareTransportHUD.clock(596.9), "09:56")
        XCTAssertEqual(SoftwareTransportHUD.clock(3599), "59:59")
    }

    func testClockShowsHoursFromAnHour() {
        XCTAssertEqual(SoftwareTransportHUD.clock(3600), "1:00:00")
        XCTAssertEqual(SoftwareTransportHUD.clock(3723), "1:02:03")
    }

    func testClockTreatsNonFiniteAsZero() {
        XCTAssertEqual(SoftwareTransportHUD.clock(.nan), "00:00")
        XCTAssertEqual(SoftwareTransportHUD.clock(.infinity), "00:00")
    }

    func testMenusFillTheRowAndRowFocusNeedsMenus() {
        let hud = SoftwareTransportHUD(title: "Title")
        hud.focusRow()
        XCTAssertFalse(hud.rowFocused)
        hud.setMenus([UIMenu(title: "Audio", children: []), UIMenu(title: "Settings", children: [])])
        XCTAssertTrue(hud.hasMenus)
        hud.focusRow()
        XCTAssertTrue(hud.rowFocused)
        XCTAssertTrue(hud.wantsFocus)
        hud.setMenus([])
        XCTAssertFalse(hud.rowFocused)
        XCTAssertFalse(hud.hasMenus)
    }
}
