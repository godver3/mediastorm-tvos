import XCTest

/// Going to the Watchlist tab and back to Home must land on Home, not push a details page.
@MainActor
final class TabReturnUITests: XCTestCase {
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
            .write(to: URL(fileURLWithPath: dir).appendingPathComponent(String(format: "t%02d-%@.png", step, name)))
    }

    private var focusedLabel: String {
        let focused = app.descendants(matching: .any).element(matching: NSPredicate(format: "hasFocus == true"))
        return focused.exists ? focused.label : ""
    }

    private func press(_ button: XCUIRemote.Button, _ times: Int = 1, gap: TimeInterval = 0.8) {
        for _ in 0..<times {
            remote.press(button)
            Thread.sleep(forTimeInterval: gap)
        }
    }

    private var onHome: Bool { app.staticTexts["Continue Watching"].exists }

    func testWatchlistTabAndBackStaysOnHome() throws {
        app.launchArguments += ["-StrmrAutoSignIn", "1"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Continue Watching"].waitForExistence(timeout: 40))
        Thread.sleep(forTimeInterval: 2)
        shot("home")

        press(.down)
        try app.focusTab("Watchlist")
        shot("watchlist", wait: 3)
        try app.focusTab("Home")
        shot("back-home", wait: 3)
        XCTAssertEqual(focusedLabel, "Home", "returning to the tab must leave focus on the tab bar")
        press(.select)
        shot("home-tab-select", wait: 3)
        XCTAssertTrue(onHome, "Select on the Home tab should not open a details page")

        // Back from details still refocuses the card that opened it.
        if focusedLabel == "Home" { press(.down) }
        press(.right)
        let card = focusedLabel
        XCTAssertFalse(card.isEmpty)
        press(.select)
        let gone = expectation(for: NSPredicate(format: "exists == false"),
                               evaluatedWith: app.staticTexts["Continue Watching"])
        wait(for: [gone], timeout: 10)
        shot("details", wait: 3)
        press(.menu)
        XCTAssertTrue(app.staticTexts["Continue Watching"].waitForExistence(timeout: 10))
        shot("back-from-details", wait: 3)
        XCTAssertEqual(focusedLabel, card, "back from details should refocus the card that opened it")
    }
}
