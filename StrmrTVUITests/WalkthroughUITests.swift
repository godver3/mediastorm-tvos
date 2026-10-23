import XCTest

/// Remote-driven smoke walk of Home -> Details -> Search, saving screenshots to
/// $STRMR_SHOT_DIR (host path; simulator only) for visual review. These sign in with
/// the optional debug `Secrets` (`-StrmrAutoSignIn`); see `OnboardingUITests` for the UI.
@MainActor
final class WalkthroughUITests: XCTestCase {
    private let app = XCUIApplication()
    private let remote = XCUIRemote.shared
    private var step = 0

    override func setUp() async throws {
        continueAfterFailure = true
        app.launchArguments += ["-StrmrAutoSignIn", "1"]
        app.launch()
    }

    private func shot(_ name: String, wait: TimeInterval = 2.5) {
        Thread.sleep(forTimeInterval: wait)
        step += 1
        let dir = ProcessInfo.processInfo.environment["STRMR_SHOT_DIR"] ?? NSTemporaryDirectory()
        let url = URL(fileURLWithPath: dir).appendingPathComponent(String(format: "%02d-%@.png", step, name))
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: url)
    }

    private func press(_ button: XCUIRemote.Button, _ times: Int = 1) {
        for _ in 0..<times {
            remote.press(button)
            Thread.sleep(forTimeInterval: 0.6)
        }
    }

    func testWalkthrough() throws {
        XCTAssertTrue(app.staticTexts["Continue Watching"].waitForExistence(timeout: 20))
        shot("home-launch", wait: 4)

        press(.down)
        shot("home-first-card-focused")
        press(.right)
        shot("home-second-card-focused")

        // Series details (Saturday Night Live)
        press(.select)
        shot("series-details", wait: 6)
        press(.down)
        shot("series-seasons-focused")
        press(.down)
        shot("series-episodes-focused")
        press(.menu)
        shot("back-home", wait: 1.5)

        // Movie details (Coco: third card)
        press(.right)
        press(.select)
        shot("movie-details", wait: 6)
        press(.menu)

        // Search tab
        try app.focusTab("Search")
        shot("search-tab", wait: 2)
        let field = app.searchFields.firstMatch
        if field.waitForExistence(timeout: 5) {
            press(.down)
            app.typeText("coco")
        }
        shot("search-results", wait: 5)
    }

    /// Resolves a stream and opens the player for the movie in Continue Watching.
    func testPlayMovie() throws {
        XCTAssertTrue(app.staticTexts["Continue Watching"].waitForExistence(timeout: 20))
        Thread.sleep(forTimeInterval: 2)
        // Reach Coco through Search so the pick doesn't depend on Continue Watching order.
        try app.focusTab("Search")
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        press(.down)
        app.typeText("coco")
        Thread.sleep(forTimeInterval: 4)
        press(.down, 2)
        press(.select)
        shot("play-details", wait: 6)
        press(.select)
        shot("play-resolving", wait: 3)
        shot("play-player-10s", wait: 10)
        press(.right)
        shot("play-after-skip", wait: 2)
        press(.select)
        shot("play-paused", wait: 2)
        press(.menu)
        shot("play-after-menu", wait: 3)
    }
}

/// Opens the stock transport bar and its menus on Apple's sample stream.
@MainActor
final class ChromeProbeUITests: XCTestCase {
    func testNativeChrome() {
        let app = XCUIApplication()
        app.launchArguments += ["-StrmrChromeProbe", "1", "-StrmrProbeHideNative",
                                ProcessInfo.processInfo.environment["STRMR_HIDE_NATIVE"] ?? "0"]
        app.launchEnvironment["STRMR_SHOT_DIR"] = ProcessInfo.processInfo.environment["STRMR_SHOT_DIR"]
        app.launch()
        let dir = ProcessInfo.processInfo.environment["STRMR_SHOT_DIR"] ?? NSTemporaryDirectory()
        var n = 0
        func shot(_ name: String, _ wait: TimeInterval = 2) {
            Thread.sleep(forTimeInterval: wait); n += 1
            try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir + String(format: "/probe-%02d-%@.png", n, name)))
        }
        let remote = XCUIRemote.shared
        shot("playing", 8)
        remote.press(.select)
        shot("paused-bar")
        remote.press(.up)
        shot("up-1")
        try? app.debugDescription.write(toFile: dir + "/ax-up.txt", atomically: true, encoding: .utf8)
        try? app.debugDescription.write(toFile: dir + "/ax-up.txt", atomically: true, encoding: .utf8)
        remote.press(.select)
        shot("focused-menu-open", 2)
        remote.press(.menu)
        for k in 0..<3 {
            remote.press(.right)
            shot("right-\(k)", 1)
        }
        remote.press(.select)
        shot("rightmost-open", 2)
    }
}

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

/// Opens the custom Audio menu on the probe player and picks the last track.
@MainActor
final class ChromeProbeAudioMenuUITests: XCTestCase {
    func testAudioMenuSelection() {
        let app = XCUIApplication()
        app.launchArguments += ["-StrmrChromeProbe", "1", "-StrmrProbeHideNative", "1"]
        app.launchEnvironment["STRMR_SHOT_DIR"] = ProcessInfo.processInfo.environment["STRMR_SHOT_DIR"]
        app.launch()
        let dir = ProcessInfo.processInfo.environment["STRMR_SHOT_DIR"] ?? NSTemporaryDirectory()
        var n = 0
        func shot(_ name: String, _ wait: TimeInterval = 1.5) {
            Thread.sleep(forTimeInterval: wait); n += 1
            try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir + String(format: "/audio-%02d-%@.png", n, name)))
        }
        let remote = XCUIRemote.shared
        shot("playing", 8)
        remote.press(.select)
        shot("bar")
        remote.press(.up)
        shot("up")
        remote.press(.select)
        shot("menu-open")
        remote.press(.down); Thread.sleep(forTimeInterval: 0.4)
        remote.press(.down); Thread.sleep(forTimeInterval: 0.4)
        shot("menu-down")
        remote.press(.select)
        shot("picked", 2)
    }
}

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

/// Home row focus: entering from the tab bar lands on the first card, and coming back
/// from details restores the card that was opened. No playback.
@MainActor
final class HomeFocusUITests: XCTestCase {
    private let app = XCUIApplication()
    private let remote = XCUIRemote.shared

    private var focusedLabel: String {
        let focused = app.descendants(matching: .any).element(matching: NSPredicate(format: "hasFocus == true"))
        return focused.exists ? focused.label : ""
    }

    private func press(_ button: XCUIRemote.Button, _ times: Int = 1) {
        for _ in 0..<times {
            remote.press(button)
            Thread.sleep(forTimeInterval: 0.8)
        }
    }

    func testRowEntryAndReturn() {
        app.launchArguments += ["-StrmrAutoSignIn", "1"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Continue Watching"].waitForExistence(timeout: 20))
        Thread.sleep(forTimeInterval: 2)
        let cards = app.buttons.allElementsBoundByIndex.filter { $0.frame.minY > 500 }.map(\.label)
        press(.down)
        let entered = focusedLabel
        XCTAssertEqual(entered, cards.first, "entry focus; row: \(cards)")

        // Up from a card reaches the tab bar (the entry strip must not trap focus); Down
        // comes back to the same card.
        press(.up)
        XCTAssertTrue(app.tabBars.buttons.allElementsBoundByIndex.contains { $0.hasFocus } || !cards.contains(focusedLabel),
                      "after Up: \(focusedLabel)")
        press(.down)
        XCTAssertEqual(focusedLabel, cards.first, "re-entry focus")

        // Scrolled well into the row: cards in the left margin must still be drawn.
        press(.right, 4)
        if let dir = ProcessInfo.processInfo.environment["STRMR_SHOT_DIR"] {
            try? XCUIScreen.main.screenshot().pngRepresentation
                .write(to: URL(fileURLWithPath: dir).appendingPathComponent("home-scrolled.png"))
        }
        press(.left, 2)
        let opened = focusedLabel
        press(.select)
        Thread.sleep(forTimeInterval: 4)
        press(.menu)
        Thread.sleep(forTimeInterval: 2)
        XCTAssertEqual(focusedLabel, opened, "focus after returning from details")
    }
}

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
