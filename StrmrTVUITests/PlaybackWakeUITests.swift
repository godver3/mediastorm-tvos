import XCTest

/// Resumes Coco (moves its watch progress by the ~30 s played), checks the subtitle pick
/// renders, then backgrounds the app and expects to come back to details with Resume.
@MainActor
final class PlaybackWakeUITests: XCTestCase {
    override func setUp() async throws {
        // Never press Play on anything but the intended title.
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
            .write(to: URL(fileURLWithPath: dir).appendingPathComponent(String(format: "w%02d-%@.png", step, name)))
    }

    private var focusedLabel: String {
        let focused = app.descendants(matching: .any).element(matching: NSPredicate(format: "hasFocus == true"))
        return focused.exists ? focused.label : ""
    }

    /// Opens Coco's details through Search so the pick never depends on row order.
    private func openCoco() throws {
        XCTAssertTrue(app.staticTexts["Continue Watching"].waitForExistence(timeout: 20))
        Thread.sleep(forTimeInterval: 2)
        try app.openFromSearch("coco", title: "Coco")
        XCTAssertTrue(focusedLabel.hasPrefix("Resume from"), "focused: \(focusedLabel)")
    }

    func testResumeThenMenu() throws {
        app.launchArguments += ["-StrmrAutoSignIn", "1"]
        app.launch()
        try openCoco()
        remote.press(.select)
        shot("menu-playing", wait: 15)
        remote.press(.menu)
        shot("menu-closed", wait: 4)
    }

    func testResumeThenBackground() throws {
        app.launchArguments += ["-StrmrAutoSignIn", "1"]
        app.launch()
        try openCoco()
        XCTAssertTrue(focusedLabel.contains("Resume"), "focused: \(focusedLabel)")
        remote.press(.select)
        shot("playing-subtitles", wait: 30)
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 5)
        app.activate()
        shot("after-wake", wait: 5)
        XCTAssertTrue(app.buttons.containing(NSPredicate(format: "label BEGINSWITH 'Resume'")).firstMatch.waitForExistence(timeout: 10))
    }
}
