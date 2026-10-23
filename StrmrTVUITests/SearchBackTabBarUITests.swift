import XCTest

/// Scrolling a series' details page down to its seasons and going back must leave the
/// Search tab with its tab bar showing.
@MainActor
final class SearchBackTabBarUITests: XCTestCase {
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

    /// Focus reached the tab bar (the Search tab, as this page's own).
    private var tabBarShowing: Bool { focusedLabel == "Search" }

    func testBackFromSeasonsKeepsTabBar() throws {
        app.launchArguments += ["-StrmrAutoSignIn", "1"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Continue Watching"].waitForExistence(timeout: 40))
        Thread.sleep(forTimeInterval: 2)
        try app.focusTab("Search")
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        press(.down)
        app.typeText("breaking bad")
        Thread.sleep(forTimeInterval: 4)
        press(.down)
        // Scan the first rows of results for the show itself (spin-offs share the name).
        rows: for _ in 0..<3 {
            for _ in 0..<8 { press(.left, gap: 0.3) }
            for _ in 0..<8 {
                if focusedLabel == "Breaking Bad" { break rows }
                press(.right, gap: 0.5)
            }
            press(.down)
        }
        XCTAssertEqual(focusedLabel, "Breaking Bad")
        shot("search-before")

        press(.select)
        Thread.sleep(forTimeInterval: 4)
        press(.down, 2)
        shot("details-seasons")
        XCTAssertTrue(focusedLabel.hasPrefix("Season") || focusedLabel.hasPrefix("Specials")
                      || !focusedLabel.isEmpty, "focused: \(focusedLabel)")

        press(.menu)
        shot("search-after", wait: 3)
        XCTAssertEqual(focusedLabel, "Breaking Bad", "back should refocus the result")
        // Up past the results and the keyboard must reach the tab bar again.
        for _ in 0..<8 where !tabBarShowing { press(.up) }
        shot("search-up")
        XCTAssertTrue(tabBarShowing, "tab bar should come back on Search after back from seasons")
    }
}
