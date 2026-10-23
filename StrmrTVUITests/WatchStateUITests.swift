import XCTest

/// The watched controls on details: the series Watch State screen, the episode long-press
/// toggle and the movie toggle. Read-only: it opens them and closes them again without
/// pressing anything that writes, so the profile's history is untouched.
@MainActor
final class WatchStateUITests: XCTestCase {
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
            .write(to: URL(fileURLWithPath: dir).appendingPathComponent(String(format: "s%02d-%@.png", step, name)))
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

    /// Moves right along the action row until `label` has focus.
    private func focusAction(_ label: String) {
        for _ in 0..<6 where focusedLabel != label {
            press(.right)
        }
        XCTAssertEqual(focusedLabel, label)
    }

    /// Opens details for the first card of the Home row `rowsDown` rows below the hero.
    private func openHomeCard(rowsDown: Int) {
        app.launchArguments += ["-StrmrAutoSignIn", "1"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Continue Watching"].waitForExistence(timeout: 40))
        Thread.sleep(forTimeInterval: 2)
        press(.down, rowsDown)
        press(.select)
        Thread.sleep(forTimeInterval: 5)
    }

    func testSeriesWatchStateAndEpisodeToggle() {
        // Trending Shows (the fourth row) is always a series.
        openHomeCard(rowsDown: 4)
        XCTAssertTrue(app.buttons["Watch State"].waitForExistence(timeout: 20), "series details should offer Watch State")
        shot("series-details")

        focusAction("Watch State")
        press(.select)
        XCTAssertTrue(app.buttons["WatchState-all-watched"].waitForExistence(timeout: 5))
        shot("watch-state")
        press(.down, 6, gap: 0.4)
        shot("watch-state-seasons")
        press(.menu)
        Thread.sleep(forTimeInterval: 2)
        XCTAssertFalse(app.buttons["WatchState-all-watched"].exists, "Menu should close Watch State")

        // Down to the episode row and long-press the first episode.
        press(.down, 2)
        let episode = focusedLabel
        XCTAssertTrue(episode.hasPrefix("Episode"), "focused: \(episode)")
        remote.press(.select, forDuration: 1.5)
        shot("episode-menu", wait: 1)
        let toggle = episode.hasSuffix(", watched") ? "Mark as Unwatched" : "Mark as Watched"
        XCTAssertTrue(app.descendants(matching: .any)[toggle].waitForExistence(timeout: 5),
                      "long-press menu should offer \(toggle)")
        press(.menu)
        shot("episode-menu-closed", wait: 1)
    }

    func testMovieWatchedToggle() {
        // Trending Movies (the third row) is always a movie.
        openHomeCard(rowsDown: 3)
        let toggle = app.buttons.matching(NSPredicate(format: "label IN %@", ["Mark as Watched", "Watched"])).firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 20), "movie details should offer the watched toggle")
        XCTAssertFalse(app.buttons["Watch State"].exists)
        shot("movie-details")
    }
}
