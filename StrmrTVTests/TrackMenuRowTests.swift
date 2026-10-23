import XCTest
@testable import StrmrTV

/// The player's Audio / Subtitles menu rows are one line each (AVKit's menu
/// mislaid two-line rows when Down was held through a long list).
@MainActor
final class TrackMenuRowTests: XCTestCase {
    private func row(_ title: String, _ detail: String?) -> String {
        NativeChrome.rowTitle(TrackMenuItem(id: 1, title: title, detail: detail, isSelected: false))
    }

    func testShortRowJoinsTitleAndDetail() {
        XCTAssertEqual(row("English", "SDH · SRT"), "English · SDH · SRT")
        XCTAssertEqual(row("Off", nil), "Off")
        XCTAssertEqual(row("English", ""), "English")
    }

    func testLongRowCutsTheMiddleAndKeepsTheFormat() {
        let long = row("English", "Forced · Signs & Songs [Group] (Modified, Netflix rip) · ASS")
        XCTAssertTrue(long.hasPrefix("English · "), long)
        XCTAssertTrue(long.hasSuffix(" · ASS"), long)
        XCTAssertTrue(long.contains("…"), long)
        XCTAssertFalse(long.contains("\n"))
    }

    func testLongTitleWithoutDetailIsCut() {
        let long = row("Signs & Songs [Group] (Modified, Netflix rip) with a very long name", nil)
        XCTAssertTrue(long.hasSuffix("…"), long)
    }
}
