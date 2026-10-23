import XCTest

/// Fresh-install startup through the real screens: server → sign in → profile (PIN)
/// → Home → Settings → sign out. Fields are prefilled from the optional debug
/// `Secrets`, so the test only moves focus and presses buttons. No playback.
@MainActor
final class OnboardingUITests: XCTestCase {
    private let app = XCUIApplication()
    private let remote = XCUIRemote.shared
    private var step = 0

    override func setUp() async throws {
        continueAfterFailure = false
    }

    private func shot(_ name: String, wait: TimeInterval = 1.5) {
        Thread.sleep(forTimeInterval: wait)
        step += 1
        let dir = ProcessInfo.processInfo.environment["STRMR_SHOT_DIR"] ?? NSTemporaryDirectory()
        try? XCUIScreen.main.screenshot().pngRepresentation
            .write(to: URL(fileURLWithPath: dir).appendingPathComponent(String(format: "o%02d-%@.png", step, name)))
    }

    private var focusedLabel: String {
        let focused = app.descendants(matching: .any).element(matching: NSPredicate(format: "hasFocus == true"))
        return focused.exists ? focused.label : ""
    }

    @discardableResult
    private func moveFocus(_ direction: XCUIRemote.Button, to label: String, max: Int = 8) -> Bool {
        for _ in 0..<max {
            if focusedLabel == label { return true }
            remote.press(direction)
            Thread.sleep(forTimeInterval: 0.5)
        }
        return focusedLabel == label
    }

    /// Types `pin` on the PIN pad by moving focus between keys (focus starts on 1 and
    /// returns there after a wrong PIN). Layout: 1-9 in rows of three, then _ 0 delete.
    private func enterPIN(_ pin: String) {
        var row = 0, col = 0
        func move(_ button: XCUIRemote.Button, _ count: Int) {
            for _ in 0..<count {
                remote.press(button)
                Thread.sleep(forTimeInterval: 0.35)
            }
        }
        for ch in pin {
            guard let d = Int(String(ch)) else { continue }
            let (r, c) = d == 0 ? (3, 1) : ((d - 1) / 3, (d - 1) % 3)
            func horizontal() { c > col ? move(.right, c - col) : move(.left, col - c) }
            func vertical() { r > row ? move(.down, r - row) : move(.up, row - r) }
            // Never pass through the empty cell left of 0.
            if row == 3 { vertical(); horizontal() } else { horizontal(); vertical() }
            row = r; col = c
            remote.press(.select)
            Thread.sleep(forTimeInterval: 0.35)
        }
        row = 0; col = 0
    }

    func testFreshSignInAndSignOut() {
        app.launchArguments += ["-StrmrResetSession", "1"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Connect to Your Server"].waitForExistence(timeout: 10))
        shot("server")
        XCTAssertTrue(moveFocus(.down, to: "Connect"), "focused: \(focusedLabel)")
        remote.press(.select)

        XCTAssertTrue(app.staticTexts["Sign In"].waitForExistence(timeout: 15))
        shot("login")
        XCTAssertTrue(moveFocus(.down, to: "Sign In"), "focused: \(focusedLabel)")
        remote.press(.select)

        XCTAssertTrue(app.staticTexts["Who's Watching?"].waitForExistence(timeout: 15))
        shot("profiles")
        remote.press(.select)
        let pinTitle = app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH 'Enter PIN for'")).firstMatch
        if pinTitle.waitForExistence(timeout: 3) {
            shot("pin-pad")
            // One wrong attempt to check the error state, then the real PIN.
            let pin = ProcessInfo.processInfo.environment["STRMR_PIN"] ?? ""
            XCTAssertFalse(pin.isEmpty, "set TEST_RUNNER_STRMR_PIN to the test profile's PIN")
            enterPIN(String(repeating: "9", count: pin.count))
            shot("pin-wrong", wait: 2.5)
            enterPIN(pin)
        }

        XCTAssertTrue(app.staticTexts["Continue Watching"].waitForExistence(timeout: 20))
        shot("home", wait: 3)

        remote.press(.up)
        Thread.sleep(forTimeInterval: 0.6)
        XCTAssertTrue(moveFocus(.right, to: "Settings"), "focused: \(focusedLabel)")
        Thread.sleep(forTimeInterval: 1)
        shot("settings", wait: 3)
        remote.press(.down)
        XCTAssertTrue(moveFocus(.down, to: "Sign Out", max: 14), "focused: \(focusedLabel)")
        shot("settings-sign-out-focused")
        remote.press(.select)
        shot("sign-out-confirm")
        XCTAssertTrue(moveFocus(.right, to: "Sign Out", max: 3), "focused: \(focusedLabel)")
        remote.press(.select)

        XCTAssertTrue(app.staticTexts["Sign In"].waitForExistence(timeout: 10))
        shot("signed-out")
    }

    /// After a sign-in, a relaunch restores the session from the Keychain and goes
    /// to Home or, unless a profile is set to open automatically, to the picker.
    func testRelaunchRestoresSession() {
        app.launchArguments += ["-StrmrResetSession", "1", "-StrmrAutoSignIn", "1"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Continue Watching"].waitForExistence(timeout: 30))
        app.terminate()

        let relaunch = XCUIApplication()
        relaunch.launch()
        let home = relaunch.staticTexts["Continue Watching"]
        let picker = relaunch.staticTexts["Who's Watching?"]
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline, !home.exists, !picker.exists { Thread.sleep(forTimeInterval: 0.5) }
        shot("relaunch")
        XCTAssertTrue(home.exists || picker.exists)
        XCTAssertFalse(relaunch.staticTexts["Sign In"].exists)
    }
}
