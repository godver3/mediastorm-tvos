import XCTest

/// Remote-driven smoke walk of Home -> Details -> Search, saving screenshots to
/// $STRMR_SHOT_DIR (host path; simulator only) for visual review. These sign in with
/// the optional debug `Secrets` (`-StrmrAutoSignIn`); see `OnboardingUITests` for the UI.
@MainActor
final class WalkthroughUITests: XCTestCase {
    private let app = XCUIApplication()
    private let remote = XCUIRemote.shared
    private var step = 0

    override func setUp() async throws {
        continueAfterFailure = true
        app.launchArguments += ["-StrmrAutoSignIn", "1"]
        app.launch()
    }

    private func shot(_ name: String, wait: TimeInterval = 2.5) {
        Thread.sleep(forTimeInterval: wait)
        step += 1
        let dir = ProcessInfo.processInfo.environment["STRMR_SHOT_DIR"] ?? NSTemporaryDirectory()
        let url = URL(fileURLWithPath: dir).appendingPathComponent(String(format: "%02d-%@.png", step, name))
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: url)
    }

    private func press(_ button: XCUIRemote.Button, _ times: Int = 1) {
        for _ in 0..<times {
            remote.press(button)
            Thread.sleep(forTimeInterval: 0.6)
        }
    }

    func testWalkthrough() throws {
        XCTAssertTrue(app.staticTexts["Continue Watching"].waitForExistence(timeout: 20))
        shot("home-launch", wait: 4)

        press(.down)
        shot("home-first-card-focused")
        press(.right)
        shot("home-second-card-focused")

        // Series details (Saturday Night Live)
        press(.select)
        shot("series-details", wait: 6)
        press(.down)
        shot("series-seasons-focused")
        press(.down)
        shot("series-episodes-focused")
        press(.menu)
        shot("back-home", wait: 1.5)

        // Movie details (Coco: third card)
        press(.right)
        press(.select)
        shot("movie-details", wait: 6)
        press(.menu)

        // Search tab
        try app.focusTab("Search")
        shot("search-tab", wait: 2)
        let field = app.searchFields.firstMatch
        if field.waitForExistence(timeout: 5) {
            press(.down)
            app.typeText("coco")
        }
        shot("search-results", wait: 5)
    }

    /// Resolves a stream and opens the player for the movie in Continue Watching.
    func testPlayMovie() throws {
        XCTAssertTrue(app.staticTexts["Continue Watching"].waitForExistence(timeout: 20))
        Thread.sleep(forTimeInterval: 2)
        // Reach Coco through Search so the pick doesn't depend on Continue Watching order.
        try app.focusTab("Search")
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        press(.down)
        app.typeText("coco")
        Thread.sleep(forTimeInterval: 4)
        press(.down, 2)
        press(.select)
        shot("play-details", wait: 6)
        press(.select)
        shot("play-resolving", wait: 3)
        shot("play-player-10s", wait: 10)
        press(.right)
        shot("play-after-skip", wait: 2)
        press(.select)
        shot("play-paused", wait: 2)
        press(.menu)
        shot("play-after-menu", wait: 3)
    }
}
