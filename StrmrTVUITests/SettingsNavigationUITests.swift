import XCTest

/// The Settings tab: the focused row isn't clipped, and the tab bar comes back after a
/// subpage (Home Layout) is closed with Menu. Read-only.
@MainActor
final class SettingsNavigationUITests: XCTestCase {
    override func setUp() async throws {
        continueAfterFailure = false
    }

    private let app = XCUIApplication()
    private let remote = XCUIRemote.shared
    private var step = 0

    private func shot(_ name: String, wait: TimeInterval = 1.5) {
        Thread.sleep(forTimeInterval: wait)
        step += 1
        let dir = ProcessInfo.processInfo.environment["STRMR_SHOT_DIR"] ?? NSTemporaryDirectory()
        try? XCUIScreen.main.screenshot().pngRepresentation
            .write(to: URL(fileURLWithPath: dir).appendingPathComponent(String(format: "nav%02d-%@.png", step, name)))
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

    /// The tab bar slides off the top of the screen when tvOS hides it.
    private var tabBarVisible: Bool {
        let bar = app.tabBars.firstMatch
        print("[nav] tab bar exists=\(bar.exists) frame=\(bar.frame)")
        return bar.exists && bar.frame.maxY > 0 && bar.frame.height > 0
    }

    func testTabBarReturnsAfterSubpage() {
        app.launchArguments += ["-StrmrAutoSignIn", "1"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Continue Watching"].waitForExistence(timeout: 40))
        Thread.sleep(forTimeInterval: 2)
        press(.down)
        press(.up)
        moveFocus(.right, to: "Settings", max: 8)
        press(.down)
        shot("settings-top")
        moveFocus(.down, to: "Home Layout")
        shot("settings-home-layout-row")
        press(.select)
        XCTAssertTrue(app.staticTexts["Home Layout"].waitForExistence(timeout: 5))
        // Deep enough that tvOS hides the tab bar while scrolling.
        press(.down, 15, gap: 0.4)
        shot("home-layout-deep")
        press(.menu)
        shot("back-on-settings")
        XCTAssertTrue(focusedLabel.hasPrefix("Home Layout"), "focus after Menu: \(focusedLabel)")
        XCTAssertTrue(tabBarVisible, "tab bar should be back after returning from Home Layout")

        moveFocus(.down, to: "Subtitle Style")
        press(.select)
        XCTAssertTrue(app.staticTexts["Subtitle Style"].waitForExistence(timeout: 5))
        shot("subtitle-style")
        press(.down, 12, gap: 0.4)
        shot("subtitle-style-deep")
        moveFocus(.up, to: "Size", max: 16)
        press(.select)
        shot("size-list")
        press(.menu)
        press(.menu)
        shot("back-from-subtitles")
        XCTAssertTrue(tabBarVisible, "tab bar should be back after returning from Subtitle Style")
    }

    /// A picker's option list (Home Layout › Hero Size) shows its options, not a blank page.
    func testPickerOptionsShow() {
        app.launchArguments += ["-StrmrAutoSignIn", "1"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Continue Watching"].waitForExistence(timeout: 40))
        Thread.sleep(forTimeInterval: 2)
        press(.down)
        press(.up)
        moveFocus(.right, to: "Settings", max: 8)
        press(.down)
        moveFocus(.down, to: "Home Layout")
        press(.select)
        XCTAssertTrue(app.staticTexts["Home Layout"].waitForExistence(timeout: 5))
        moveFocus(.down, to: "Hero Size")
        press(.select)
        shot("hero-size-options")
        XCTAssertTrue(focusedLabel.hasPrefix("Default"), "options should show, focused: \(focusedLabel)")
        // Back out: shots through the pop, for the row's value drawing during the transition.
        remote.press(.menu)
        for i in 0..<6 { shot("back-\(i)", wait: 0.05) }
    }
}
