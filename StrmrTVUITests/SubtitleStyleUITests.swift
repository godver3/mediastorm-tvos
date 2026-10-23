import XCTest

/// Settings > Subtitle Style (device-local) with its live preview. Changes only this
/// device's UserDefaults (the subtitle style), never the profile.
@MainActor
final class SubtitleStyleUITests: XCTestCase {
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
            .write(to: URL(fileURLWithPath: dir).appendingPathComponent(String(format: "sub%02d-%@.png", step, name)))
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

    private func moveFocus(_ button: XCUIRemote.Button, to label: String, max: Int = 20) {
        for _ in 0..<max where !focusedLabel.hasPrefix(label) { press(button) }
        XCTAssertTrue(focusedLabel.hasPrefix(label), "wanted \(label), focused: \(focusedLabel)")
    }

    func testSubtitleStyleSettings() {
        app.launchArguments += ["-StrmrAutoSignIn", "1"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Continue Watching"].waitForExistence(timeout: 40))
        Thread.sleep(forTimeInterval: 2)
        press(.down)
        press(.up)
        moveFocus(.right, to: "Settings", max: 8)
        press(.down)
        moveFocus(.down, to: "Subtitle Style")
        press(.select)
        XCTAssertTrue(app.staticTexts["Subtitle Style"].waitForExistence(timeout: 5))
        shot("settings")

        // Size: open the picker, step one option down, back to the form with the preview.
        moveFocus(.down, to: "Size")
        press(.select)
        shot("size-picker", wait: 1.5)
        press(.down)
        press(.select)
        shot("size-changed", wait: 1.5)
        XCTAssertTrue(focusedLabel.hasPrefix("Size"), "the menu should close on a pick: \(focusedLabel)")

        moveFocus(.down, to: "Box Opacity")
        press(.select)
        shot("box-picker", wait: 1.5)
        press(.down)
        press(.select)
        shot("box-changed", wait: 1.5)
        XCTAssertTrue(focusedLabel.hasPrefix("Box Opacity"), "the list should close on a pick: \(focusedLabel)")
    }
}
