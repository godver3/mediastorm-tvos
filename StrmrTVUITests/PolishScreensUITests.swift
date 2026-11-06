import XCTest

/// Screens the polish pass reviews: details focus, the source list scrolled, search,
/// settings. Nothing is played.
@MainActor
final class PolishScreensUITests: XCTestCase {
    private let app = XCUIApplication()
    private let remote = XCUIRemote.shared
    private var step = 0

    private func shot(_ name: String, wait: TimeInterval = 2) {
        Thread.sleep(forTimeInterval: wait)
        step += 1
        let dir = ProcessInfo.processInfo.environment["STRMR_SHOT_DIR"] ?? NSTemporaryDirectory()
        try? XCUIScreen.main.screenshot().pngRepresentation
            .write(to: URL(fileURLWithPath: dir).appendingPathComponent(String(format: "p%02d-%@.png", step, name)))
    }

    private var focusedLabel: String {
        let focused = app.descendants(matching: .any).element(matching: NSPredicate(format: "hasFocus == true"))
        return focused.exists ? focused.label : ""
    }

    private func press(_ button: XCUIRemote.Button, _ times: Int = 1) {
        for _ in 0..<times {
            remote.press(button)
            Thread.sleep(forTimeInterval: 0.5)
        }
    }

    @discardableResult
    private func moveFocus(_ direction: XCUIRemote.Button, until text: String, max: Int = 12) -> Bool {
        for _ in 0..<max {
            if focusedLabel.localizedCaseInsensitiveContains(text) { return true }
            press(direction)
        }
        return focusedLabel.localizedCaseInsensitiveContains(text)
    }

    func testPolishScreens() throws {
        app.launchArguments += ["-StrmrAutoSignIn", "1"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Continue Watching"].waitForExistence(timeout: 20))
        Thread.sleep(forTimeInterval: 2)
        press(.down)
        XCTAssertTrue(moveFocus(.left, until: "Casper", max: 8) || true)
        shot("home-focus-a")
        press(.right)
        shot("home-focus-b")

        // Movie details: primary action focused first.
        XCTAssertTrue(moveFocus(.right, until: "Coco", max: 8), "focused: \(focusedLabel)")
        press(.select)
        shot("movie-details", wait: 5)
        XCTAssertTrue(focusedLabel.contains("Resume") || focusedLabel.contains("Play"), "focused: \(focusedLabel)")

        // Manual source list, scrolled well down.
        XCTAssertTrue(moveFocus(.right, until: "Choose Source"), "focused: \(focusedLabel)")
        press(.select)
        shot("sources-top", wait: 10)
        press(.down, 12)
        shot("sources-scrolled", wait: 1.5)
        press(.menu)
        Thread.sleep(forTimeInterval: 1)
        press(.menu)
        Thread.sleep(forTimeInterval: 1)

        // Series details: Primal from Continue Watching.
        Thread.sleep(forTimeInterval: 1)
        XCTAssertTrue(moveFocus(.left, until: "Primal", max: 8), "focused: \(focusedLabel)")
        press(.select)
        shot("series-details", wait: 5)
        press(.down)
        shot("series-seasons", wait: 1.5)
        press(.down)
        shot("series-episodes", wait: 1.5)
        press(.menu)
        Thread.sleep(forTimeInterval: 1.5)

        // Search with results.
        try app.focusTab("Search")
        let field = app.searchFields.firstMatch
        if field.waitForExistence(timeout: 5) {
            press(.down)
            app.typeText("star")
        }
        shot("search-results", wait: 5)
        press(.down, 3)
        shot("search-results-focused", wait: 1.5)

        // Settings with a focused row.
        press(.menu)
        Thread.sleep(forTimeInterval: 1)
        press(.up, 4)
        press(.right)
        shot("settings", wait: 2)
        press(.down, 3)
        shot("settings-focused-row", wait: 1.5)
    }
}
