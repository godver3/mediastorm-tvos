import XCTest

/// Screenshots of the profile picker and the PIN pad (relaunch with a saved session; the
/// PIN profile opens the picker). Enters no PIN.
@MainActor
final class ProfileScreensUITests: XCTestCase {
    func testProfileScreens() {
        let app = XCUIApplication()
        app.launch()
        let dir = ProcessInfo.processInfo.environment["STRMR_SHOT_DIR"] ?? NSTemporaryDirectory()
        func shot(_ name: String) {
            Thread.sleep(forTimeInterval: 3)
            try? XCUIScreen.main.screenshot().pngRepresentation
                .write(to: URL(fileURLWithPath: dir).appendingPathComponent(name))
        }
        XCTAssertTrue(app.staticTexts["Who's Watching?"].waitForExistence(timeout: 20))
        shot("profile-picker.png")
        XCUIRemote.shared.press(.select)
        shot("pin-pad.png")
        XCUIRemote.shared.press(.right)
        shot("pin-pad-focus-2.png")
    }
}
