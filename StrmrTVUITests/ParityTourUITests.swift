import XCTest

/// Screenshots of each top-level screen, for comparing the tvOS and Android TV apps side by
/// side: Home, a Continue Watching details page, the Live guide, Watchlist, Search and
/// Settings. Saves to $STRMR_SHOT_DIR (host path; simulator only). Read-only.
@MainActor
final class ParityTourUITests: XCTestCase {
    private let app = XCUIApplication()
    private let remote = XCUIRemote.shared
    private var step = 0

    override func setUp() async throws {
        continueAfterFailure = true
        app.launchArguments += ["-StrmrAutoSignIn", "1"]
        app.launch()
    }

    private func shot(_ name: String, wait: TimeInterval = 3) {
        Thread.sleep(forTimeInterval: wait)
        step += 1
        let dir = ProcessInfo.processInfo.environment["STRMR_SHOT_DIR"] ?? NSTemporaryDirectory()
        let url = URL(fileURLWithPath: dir).appendingPathComponent(String(format: "tv%02d-%@.png", step, name))
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: url)
    }

    private func press(_ button: XCUIRemote.Button, _ times: Int = 1) {
        for _ in 0..<times {
            remote.press(button)
            Thread.sleep(forTimeInterval: 0.7)
        }
    }

    func testTour() throws {
        XCTAssertTrue(app.staticTexts["Continue Watching"].waitForExistence(timeout: 30))
        shot("home", wait: 5)
        press(.down)
        shot("home-focused")
        press(.down)
        shot("home-second-row")
        press(.up)
        press(.select)
        shot("details", wait: 7)
        press(.down)
        shot("details-down", wait: 2)
        press(.menu)
        Thread.sleep(forTimeInterval: 2)

        try? app.focusTab("Live")
        press(.down)
        shot("live", wait: 12)
        press(.down)
        shot("live-content", wait: 3)

        try? app.focusTab("Watchlist")
        press(.down)
        shot("watchlist", wait: 5)

        try? app.focusTab("Search")
        shot("search-empty")
        press(.down)
        app.typeText("dune")
        shot("search", wait: 5)
        press(.down)
        shot("search-results")

        try? app.focusTab("Settings")
        press(.down)
        shot("settings")
    }
}
