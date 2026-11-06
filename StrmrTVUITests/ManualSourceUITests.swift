import XCTest

/// Manual source selection on Coco: Choose Source -> pick -> Resume/Start Over -> play.
@MainActor
final class ManualSourceUITests: XCTestCase {
    private let app = XCUIApplication()
    private let remote = XCUIRemote.shared
    private var step = 0

    private func shot(_ name: String, wait: TimeInterval = 2) {
        Thread.sleep(forTimeInterval: wait)
        step += 1
        let dir = ProcessInfo.processInfo.environment["STRMR_SHOT_DIR"] ?? NSTemporaryDirectory()
        try? XCUIScreen.main.screenshot().pngRepresentation
            .write(to: URL(fileURLWithPath: dir).appendingPathComponent(String(format: "m%02d-%@.png", step, name)))
    }

    private var focusedLabel: String {
        let focused = app.descendants(matching: .any).element(matching: NSPredicate(format: "hasFocus == true"))
        return focused.exists ? focused.label : ""
    }

    /// Presses `direction` until the focused element's label contains `text`.
    @discardableResult
    private func moveFocus(_ direction: XCUIRemote.Button, until text: String, exact: Bool = false, max: Int = 12) -> Bool {
        func matches() -> Bool {
            exact ? focusedLabel == text : focusedLabel.localizedCaseInsensitiveContains(text)
        }
        for _ in 0..<max {
            if matches() { return true }
            remote.press(direction)
            Thread.sleep(forTimeInterval: 0.5)
        }
        return matches()
    }

    func testManualSource() {
        app.launchArguments += ["-StrmrAutoSignIn", "1"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Continue Watching"].waitForExistence(timeout: 20))
        Thread.sleep(forTimeInterval: 2)
        remote.press(.down)
        Thread.sleep(forTimeInterval: 0.6)
        XCTAssertTrue(moveFocus(.right, until: "Coco, 2017", exact: true, max: 10), "focused: \(focusedLabel)")
        remote.press(.select)
        shot("details", wait: 5)
        XCTAssertTrue(moveFocus(.right, until: "Choose Source"), "focused: \(focusedLabel)")
        remote.press(.select)
        shot("sources", wait: 10)
        remote.press(.select)
        shot("resume-dialog", wait: 2)
        remote.press(.select)
        shot("resolving", wait: 3)
        shot("player", wait: 15)
        remote.press(.menu)
        shot("closed", wait: 3)
    }
}
