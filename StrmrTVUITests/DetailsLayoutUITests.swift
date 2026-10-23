import XCTest

/// The details page opens with its header anchored to the bottom of the screen, whatever rows
/// load under it (More Like This, the collection, cast), and Down from the actions moves on to
/// those rows. Read-only: it only moves focus. Screenshots go to STRMR_SHOT_DIR when set.
@MainActor
final class DetailsLayoutUITests: XCTestCase {
    override func setUp() async throws {
        continueAfterFailure = false
    }

    private let app = XCUIApplication()
    private let remote = XCUIRemote.shared

    private var focused: XCUIElement {
        app.descendants(matching: .any).element(matching: NSPredicate(format: "hasFocus == true"))
    }

    private func press(_ button: XCUIRemote.Button, _ times: Int = 1, gap: TimeInterval = 0.8) {
        for _ in 0..<times {
            remote.press(button)
            Thread.sleep(forTimeInterval: gap)
        }
    }

    private func shot(_ name: String) {
        guard let dir = ProcessInfo.processInfo.environment["STRMR_SHOT_DIR"] else { return }
        let url = URL(fileURLWithPath: dir).appendingPathComponent("\(name).png")
        try? app.screenshot().pngRepresentation.write(to: url)
    }

    func testMovieActionsAnchoredToBottom() throws {
        try checkAnchored(query: "inception", title: "Inception", name: "movie")
    }

    func testSeriesActionsAnchoredToBottom() throws {
        try checkAnchored(query: "breaking bad", title: "Breaking Bad", name: "series")
    }

    private func checkAnchored(query: String, title: String, name: String) throws {
        app.launchArguments += ["-StrmrAutoSignIn", "1"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Continue Watching"].waitForExistence(timeout: 40))
        Thread.sleep(forTimeInterval: 2)
        try app.openFromSearch(query, title: title)
        // Long enough for the related rows (and a movie's collection) to load.
        Thread.sleep(forTimeInterval: 5)
        shot("details-\(name)-top")

        let screen = app.windows.firstMatch.frame
        let primary = focused
        XCTAssertTrue(primary.label.hasPrefix("Play") || primary.label.hasPrefix("Resume"),
                      "details should open on Play: \(primary.label)")
        // The actions sit in the bottom fifth of the screen, not floated up by the rows below.
        XCTAssertGreaterThan(primary.frame.maxY, screen.height * 0.8,
                             "actions at \(primary.frame) on a \(screen.height)-point screen")
        XCTAssertLessThanOrEqual(primary.frame.maxY, screen.height)

        // Down leaves the actions for the rows below and scrolls them into view.
        press(.down)
        let below = focused
        XCTAssertFalse(below.label.hasPrefix("Play") || below.label.hasPrefix("Resume"),
                       "Down should leave the actions: \(below.label)")
        XCTAssertLessThan(below.frame.maxY, screen.height, "the focused row should be on screen")
        shot("details-\(name)-down")
        for step in 1...4 {
            press(.down)
            shot("details-\(name)-down\(step + 1)")
        }

        // And back up to the anchored header (stopping on Play: above it is the overview).
        for _ in 0..<6 where !(focused.label.hasPrefix("Play") || focused.label.hasPrefix("Resume")) {
            press(.up)
        }
        XCTAssertTrue(focused.label.hasPrefix("Play") || focused.label.hasPrefix("Resume"),
                      "Up should return to Play: \(focused.label)")
        XCTAssertGreaterThan(focused.frame.maxY, screen.height * 0.8, "actions back at \(focused.frame)")
        shot("details-\(name)-back")
    }
}
