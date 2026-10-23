import XCTest

/// A Home row longer than 20 titles ends with an explore card that opens the whole list
/// on a page titled with the row's name; Back returns focus to the explore card.
/// Read-only: it never changes the profile's data.
@MainActor
final class ExploreCardUITests: XCTestCase {
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
            .write(to: URL(fileURLWithPath: dir).appendingPathComponent(String(format: "e%02d-%@.png", step, name)))
    }

    private var focusedLabel: String {
        let focused = app.descendants(matching: .any).element(matching: NSPredicate(format: "hasFocus == true"))
        return focused.exists ? focused.label : ""
    }

    private func press(_ button: XCUIRemote.Button, _ times: Int = 1, gap: TimeInterval = 0.5) {
        for _ in 0..<times {
            remote.press(button)
            Thread.sleep(forTimeInterval: gap)
        }
    }

    func testTrendingExploreCardOpensFullList() {
        app.launchArguments += ["-StrmrAutoSignIn", "1"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Trending Movies"].waitForExistence(timeout: 40))
        Thread.sleep(forTimeInterval: 2)

        // Continue Watching, Watchlist, then Trending Movies; along to its 21st card.
        press(.down, 3)
        press(.right, 20)
        XCTAssertTrue(focusedLabel.hasPrefix("See all"), "Expected the explore card, got \(focusedLabel)")
        shot("explore-card")

        press(.select)
        XCTAssertTrue(app.staticTexts["Trending Movies"].waitForExistence(timeout: 10))
        shot("trending-grid", wait: 4)
        press(.down, 6, gap: 0.4)
        shot("trending-grid-scrolled")

        press(.menu)
        Thread.sleep(forTimeInterval: 2)
        XCTAssertTrue(focusedLabel.hasPrefix("See all"), "Back should return to the explore card, got \(focusedLabel)")
        shot("back-on-explore-card")
    }

    /// Down from the end of a scrolled row lands on the next row's first card, not on
    /// whichever card sits under the one left; Up returns to the card left.
    func testRowEntryLandsOnFirstOrRememberedCard() {
        app.launchArguments += ["-StrmrAutoSignIn", "1"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Trending Shows"].waitForExistence(timeout: 40))
        Thread.sleep(forTimeInterval: 2)

        // Continue Watching, Watchlist, Trending Movies, Trending Shows: note its first card.
        press(.down, 4)
        let firstShow = focusedLabel
        XCTAssertFalse(firstShow.isEmpty)

        press(.up)  // Trending Movies, then along to its explore card
        press(.right, 20)
        XCTAssertTrue(focusedLabel.hasPrefix("See all"), "Expected the explore card, got \(focusedLabel)")

        press(.down, gap: 1)
        XCTAssertEqual(focusedLabel, firstShow, "Down from the row's end should land on the first card")
        shot("entry-first-card")

        press(.up, gap: 1)
        XCTAssertTrue(focusedLabel.hasPrefix("See all"), "Up should return to the card left, got \(focusedLabel)")
        shot("entry-remembered-card")
    }
}
