import XCTest

/// Home rows (Continue Watching, Watchlist, Trending Movies, Trending Shows), the
/// Watchlist tab and a watchlist title's details. Read-only: it never presses the
/// watchlist toggle or Play, so the profile's data is untouched.
@MainActor
final class WatchlistUITests: XCTestCase {
    override func setUp() async throws {
        continueAfterFailure = false
    }

    private let app = XCUIApplication()
    private let remote = XCUIRemote.shared
    private var step = 0

    private func shot(_ name: String, wait: TimeInterval = 2) {
        Thread.sleep(forTimeInterval: wait)
        step += 1
        let dir = ProcessInfo.processInfo.environment["STRMR_SHOT_DIR"] ?? NSTemporaryDirectory()
        try? XCUIScreen.main.screenshot().pngRepresentation
            .write(to: URL(fileURLWithPath: dir).appendingPathComponent(String(format: "w%02d-%@.png", step, name)))
    }

    private var focusedLabel: String {
        let focused = app.descendants(matching: .any).element(matching: NSPredicate(format: "hasFocus == true"))
        return focused.exists ? focused.label : ""
    }

    private func press(_ button: XCUIRemote.Button, _ times: Int = 1, gap: TimeInterval = 0.6) {
        for _ in 0..<times {
            remote.press(button)
            Thread.sleep(forTimeInterval: gap)
        }
    }

    func testHomeRowsAndWatchlistTab() throws {
        app.launchArguments += ["-StrmrAutoSignIn", "1"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Continue Watching"].waitForExistence(timeout: 40))
        Thread.sleep(forTimeInterval: 2)
        shot("home")

        // Into the first row, then down one row at a time: each row pins under the hero.
        press(.down)
        let first = focusedLabel
        shot("continue-watching")
        press(.down)
        XCTAssertNotEqual(focusedLabel, first, "Down should leave Continue Watching")
        shot("watchlist-row")
        press(.right, 2)
        shot("watchlist-row-right")
        press(.down)
        shot("trending-movies")
        press(.down)
        shot("trending-shows")
        press(.up, 3)
        shot("back-to-continue-watching")

        try app.focusTab("Watchlist")
        shot("watchlist-tab", wait: 4)
        press(.down)  // the filter
        press(.right)
        shot("watchlist-movies-filter", wait: 3)
        press(.left)
        press(.down)  // first poster
        let title = focusedLabel
        XCTAssertFalse(title.isEmpty, "a poster should take focus")
        shot("watchlist-poster")
        press(.select)
        XCTAssertTrue(app.buttons["In Watchlist"].waitForExistence(timeout: 15),
                      "details of a watchlist title should say In Watchlist")
        shot("details")
    }

    /// Scrolling a lower row sideways must not move the rows: the focused row stays
    /// pinned under the hero (regression: Right used to reset to the first row).
    func testRowStaysPinnedWhileScrollingSideways() {
        app.launchArguments += ["-StrmrAutoSignIn", "1"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Continue Watching"].waitForExistence(timeout: 40))
        XCTAssertTrue(app.staticTexts["Trending Movies"].waitForExistence(timeout: 20))
        Thread.sleep(forTimeInterval: 2)

        press(.down)
        press(.down, gap: 1)  // Watchlist row
        let pinnedY = app.staticTexts["Trending Movies"].frame.minY
        shot("pinned-watchlist")
        for i in 1...6 {
            press(.right, gap: 0.8)
            shot("watchlist-right-\(i)", wait: 0.5)
            XCTAssertEqual(app.staticTexts["Trending Movies"].frame.minY, pinnedY, accuracy: 4,
                           "rows moved after Right #\(i) (focused: \(focusedLabel))")
        }

        // Past the middle, the focused card stays centered on screen.
        let focusedCard = app.descendants(matching: .any).element(matching: NSPredicate(format: "hasFocus == true"))
        let screenMid = app.windows.firstMatch.frame.midX
        XCTAssertEqual(focusedCard.frame.midX, screenMid, accuracy: 60, "focused card should sit mid-screen")

        press(.down, gap: 1)  // Trending Movies
        let moviesY = app.staticTexts["Trending Movies"].frame.minY
        for i in 1...6 {
            press(.right, gap: 0.8)
            XCTAssertEqual(app.staticTexts["Trending Movies"].frame.minY, moviesY, accuracy: 4,
                           "rows moved after Right #\(i) in Trending Movies (focused: \(focusedLabel))")
        }
        shot("trending-movies-right")
    }
}
