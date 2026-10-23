import XCTest

/// Continue Watching leaves out the profile's Set Aside titles, and a card's long-press
/// menu offers hiding the title from the row. Read-only: the menu test dismisses it
/// without pressing Hide, and the hide test runs with `-StrmrDryRunHide`, so the
/// profile's watch state is untouched.
@MainActor
final class ContinueWatchingHideUITests: XCTestCase {
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
            .write(to: URL(fileURLWithPath: dir).appendingPathComponent(String(format: "cw%02d-%@.png", step, name)))
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

    /// Moves down from the tab bar to the Continue Watching row, wherever the profile's
    /// shelf config puts it, and returns the focused card's label.
    @discardableResult
    private func focusContinueWatching() -> String {
        let row = app.descendants(matching: .any)["shelf-continue-watching"]
        for _ in 0..<15 {
            press(.down)
            if row.descendants(matching: .any).element(matching: NSPredicate(format: "hasFocus == true")).exists {
                return focusedLabel
            }
        }
        XCTFail("No Continue Watching row")
        return ""
    }

    func testSetAsideFilteredAndHideInMenu() {
        app.launchArguments += ["-StrmrAutoSignIn", "1"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Continue Watching"].waitForExistence(timeout: 40))
        Thread.sleep(forTimeInterval: 2)

        // Set Aside titles (the test profile's holds MINDHUNTER) never reach the row.
        let setAside = ProcessInfo.processInfo.environment["STRMR_SET_ASIDE_TITLE"] ?? "MINDHUNTER"
        let aside = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", "\(setAside),")).firstMatch
        XCTAssertFalse(aside.exists, "\(setAside) is set aside and should not be in Continue Watching")

        focusContinueWatching()
        press(.right, 4)
        shot("continue-watching-row")

        remote.press(.select, forDuration: 1.5)
        // Context menu items surface as "Other" elements, not buttons.
        let hide = app.descendants(matching: .any)["Hide from Continue Watching"]
        XCTAssertTrue(hide.waitForExistence(timeout: 5), "the long-press menu should offer hiding")
        shot("long-press-menu", wait: 1)
        press(.menu)
    }

    /// Hiding the focused card hands focus to the card that takes its place, without
    /// first jumping to the start of the row (regression).
    func testHideKeepsFocusInPlace() {
        app.launchArguments += ["-StrmrAutoSignIn", "1", "-StrmrDryRunHide", "1"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Continue Watching"].waitForExistence(timeout: 40))
        Thread.sleep(forTimeInterval: 2)

        let first = focusContinueWatching()
        press(.right, 4)
        let hidden = focusedLabel
        press(.right)
        let next = focusedLabel
        press(.left)
        XCTAssertEqual(focusedLabel, hidden)
        shot("before-hide")

        remote.press(.select, forDuration: 1.5)
        let hide = app.descendants(matching: .any)["Hide from Continue Watching"]
        XCTAssertTrue(hide.waitForExistence(timeout: 5))
        press(.down, 2, gap: 0.4)  // past Add to List… to Hide
        remote.press(.select)

        // Sample focus while the row settles: it must never visit the first card.
        var seen: [String] = []
        let deadline = Date().addingTimeInterval(4)
        while Date() < deadline {
            let label = focusedLabel
            if !label.isEmpty, seen.last != label { seen.append(label) }
            Thread.sleep(forTimeInterval: 0.1)
        }
        print("FOCUS-SEQUENCE", seen)
        shot("after-hide", wait: 0.5)
        XCTAssertFalse(seen.contains(first), "focus jumped to the first card: \(seen)")
        XCTAssertEqual(focusedLabel, next, "focus should land on the card after the hidden one")
    }

    /// The same in the full Continue Watching grid, opened from the row's explore card.
    func testGridHideKeepsFocusInPlace() {
        app.launchArguments += ["-StrmrAutoSignIn", "1", "-StrmrDryRunHide", "1"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Continue Watching"].waitForExistence(timeout: 40))
        Thread.sleep(forTimeInterval: 2)

        focusContinueWatching()
        press(.right, 20, gap: 0.4)
        XCTAssertTrue(focusedLabel.hasPrefix("See all"), "Expected the explore card, got \(focusedLabel)")
        press(.select)
        Thread.sleep(forTimeInterval: 3)
        let first = focusedLabel
        press(.right)
        let hidden = focusedLabel
        press(.right)
        let next = focusedLabel
        press(.left)
        XCTAssertEqual(focusedLabel, hidden)
        shot("grid-before-hide")

        remote.press(.select, forDuration: 1.5)
        let hide = app.descendants(matching: .any)["Hide from Continue Watching"]
        XCTAssertTrue(hide.waitForExistence(timeout: 5))
        press(.down, 2, gap: 0.4)  // past Add to List… to Hide
        remote.press(.select)

        var seen: [String] = []
        let deadline = Date().addingTimeInterval(4)
        while Date() < deadline {
            let label = focusedLabel
            if !label.isEmpty, seen.last != label { seen.append(label) }
            Thread.sleep(forTimeInterval: 0.1)
        }
        print("GRID-FOCUS-SEQUENCE", seen)
        shot("grid-after-hide", wait: 0.5)
        XCTAssertFalse(seen.contains(first), "focus jumped to the first card: \(seen)")
        XCTAssertEqual(focusedLabel, next, "focus should land on the card after the hidden one")
    }
}
