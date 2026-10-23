import XCTest

/// The Live tab: the guide (focus, paging the window right and back), the channel cards,
/// and the Favorites filter. Read-only: nothing is favorited, hidden or played.
@MainActor
final class LiveUITests: XCTestCase {
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
            .write(to: URL(fileURLWithPath: dir).appendingPathComponent(String(format: "live%02d-%@.png", step, name)))
    }

    private var focusedLabel: String {
        let focused = app.descendants(matching: .any).element(matching: NSPredicate(format: "hasFocus == true"))
        return focused.exists ? focused.label : ""
    }

    /// The channel count beside the filters ("34 channels"), which changes with the category.
    private var filterLabel: String {
        let count = app.staticTexts.matching(NSPredicate(format: "label ENDSWITH ' channels'")).firstMatch
        return count.exists ? count.label : ""
    }

    private func press(_ button: XCUIRemote.Button, _ times: Int = 1, gap: TimeInterval = 0.6) {
        for _ in 0..<times {
            remote.press(button)
            Thread.sleep(forTimeInterval: gap)
        }
    }

    func testGuideAndCards() throws {
        app.launchArguments += ["-StrmrAutoSignIn", "1"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Continue Watching"].waitForExistence(timeout: 40))
        Thread.sleep(forTimeInterval: 2)

        try app.focusTab("Live")
        XCTAssertTrue(app.textFields.firstMatch.waitForExistence(timeout: 20), "the Live tab's search field")
        shot("live-tab", wait: 6)

        // Into the guide.
        press(.down, 2)
        let first = focusedLabel
        shot("guide-focus", wait: 3)
        press(.down, 3)
        shot("guide-down", wait: 2)
        // Right to the end of the row and past it: the window pages.
        press(.right, 6)
        shot("guide-paged-right", wait: 2)
        press(.left, 8)
        shot("guide-back-left", wait: 2)
        XCTAssertFalse(first.isEmpty, "a guide cell should take focus")

        // Up to the tab bar, down into the controls, then left to the view menu (first).
        press(.up, 10, gap: 0.4)
        press(.down)
        press(.left, 6, gap: 0.4)
        shot("controls")
        // The view menu (XCUITest doesn't report focus on a tvOS Menu; the shots show it).
        // It opens on its first entry, Guide.
        press(.select)
        shot("view-menu", wait: 1.5)
        press(.select)
        shot("guide-from-menu", wait: 6)
        press(.down)
        shot("guide-focus-again", wait: 3)
    }

    /// Menu inside the guide jumps to the category picker; down comes back to the same cell,
    /// and a new category lands focus on its first channel.
    func testGuideMenuToCategories() throws {
        app.launchArguments += ["-StrmrAutoSignIn", "1"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Continue Watching"].waitForExistence(timeout: 40))
        Thread.sleep(forTimeInterval: 2)
        try app.focusTab("Live")
        XCTAssertTrue(app.textFields.firstMatch.waitForExistence(timeout: 20), "the Live tab's search field")
        Thread.sleep(forTimeInterval: 5)

        // Deep into the guide.
        press(.down, 2)
        press(.down, 8, gap: 0.4)
        press(.right)
        let deep = focusedLabel
        shot("menu-deep", wait: 2)
        XCTAssertFalse(deep.isEmpty, "a guide cell should take focus")

        // Menu: up to the controls, still on the Live tab.
        press(.menu)
        shot("menu-on-filter", wait: 1.5)
        XCTAssertTrue(app.textFields.firstMatch.exists, "Menu should stay on the Live tab")
        XCTAssertNotEqual(focusedLabel, deep, "focus should leave the guide")

        // Down: back on the cell Menu left from.
        press(.down)
        Thread.sleep(forTimeInterval: 1.5)
        shot("menu-back-down")
        XCTAssertEqual(focusedLabel, deep, "down from the controls should restore the guide cell")

        // Menu, then pick the first category: focus lands on the new list's first channel.
        press(.menu)
        Thread.sleep(forTimeInterval: 1)
        press(.select)
        shot("filter-menu", wait: 1.5)
        press(.down, 3, gap: 0.5)
        press(.select)
        Thread.sleep(forTimeInterval: 6)
        shot("category-top")
        let top = focusedLabel
        XCTAssertFalse(top.isEmpty, "focus should drop into the new category")

        // Menu on the controls behaves as before (leaves for the tab bar).
        press(.menu)
        Thread.sleep(forTimeInterval: 1)
        press(.menu)
        shot("menu-from-filter", wait: 1.5)
    }

    /// Menu then down, several times over from deep in the guide: each time focus comes
    /// back to the same cell.
    func testGuideMenuDownRepeats() throws {
        app.launchArguments += ["-StrmrAutoSignIn", "1"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Continue Watching"].waitForExistence(timeout: 40))
        Thread.sleep(forTimeInterval: 2)
        try app.focusTab("Live")
        XCTAssertTrue(app.textFields.firstMatch.waitForExistence(timeout: 20), "the Live tab's search field")
        Thread.sleep(forTimeInterval: 5)

        press(.down, 2)
        press(.down, 12, gap: 0.4)
        press(.right)
        Thread.sleep(forTimeInterval: 1.5)
        let deep = focusedLabel
        XCTAssertFalse(deep.isEmpty, "a guide cell should take focus")
        var landed: [String] = []
        shot("repeat-deep", wait: 0.5)
        for round in 1...4 {
            press(.menu)
            shot("repeat-menu-\(round)", wait: 1)
            press(.down)
            Thread.sleep(forTimeInterval: 1.5)
            shot("repeat-\(round)")
            landed.append(focusedLabel)
        }
        XCTAssertEqual(landed, Array(repeating: deep, count: 4), "every Menu, down should come back to \(deep)")
    }

    /// Menu from a channel in a category, then a wider category (All Channels) that also
    /// has it: focus comes back to that channel, not the top of the new list.
    func testGuideNewCategoryKeepsChannel() throws {
        app.launchArguments += ["-StrmrAutoSignIn", "1"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Continue Watching"].waitForExistence(timeout: 40))
        Thread.sleep(forTimeInterval: 2)
        try app.focusTab("Live")
        XCTAssertTrue(app.textFields.firstMatch.waitForExistence(timeout: 20), "the Live tab's search field")
        Thread.sleep(forTimeInterval: 5)

        // Into a category (as in testGuideMenuToCategories), then a few channels down it.
        press(.down, 2)
        Thread.sleep(forTimeInterval: 2)
        XCTAssertFalse(focusedLabel.isEmpty, "a guide cell should take focus")
        let allLabel = filterLabel
        press(.menu)
        Thread.sleep(forTimeInterval: 1.5)
        press(.select)
        Thread.sleep(forTimeInterval: 1)
        press(.down, 3, gap: 0.5)
        press(.select)
        Thread.sleep(forTimeInterval: 6)
        XCTAssertNotEqual(filterLabel, allLabel, "a category should be picked")
        press(.down, 3, gap: 0.5)
        let deep = focusedLabel
        shot("category-deep")
        XCTAssertFalse(deep.isEmpty, "a guide cell should take focus")

        // Menu, then All Channels at the top of the picker.
        press(.menu)
        Thread.sleep(forTimeInterval: 1.5)
        press(.select)
        Thread.sleep(forTimeInterval: 1)
        press(.up, 12, gap: 0.3)
        shot("picker-all", wait: 1)
        press(.select)
        Thread.sleep(forTimeInterval: 8)
        shot("all-channels")
        // (The count itself can move: event channels come and go on the server.)
        let picker = app.descendants(matching: .any)["live.filterMenu"]
        XCTAssertTrue(picker.label.contains("All Channels"), "back on All Channels: \(picker.label)")
        XCTAssertEqual(focusedLabel, deep, "a new category that has the channel should land on it")
    }

    /// The same in the Channels grid: Menu to the category picker, down back to the card.
    func testGridMenuToCategories() throws {
        app.launchArguments += ["-StrmrAutoSignIn", "1", "-live.mode", "channels"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Continue Watching"].waitForExistence(timeout: 40))
        Thread.sleep(forTimeInterval: 2)
        try app.focusTab("Live")
        XCTAssertTrue(app.textFields.firstMatch.waitForExistence(timeout: 20), "the Live tab's search field")
        Thread.sleep(forTimeInterval: 5)

        press(.down, 2)
        press(.down, 3, gap: 0.6)
        press(.right)
        let deep = focusedLabel
        shot("grid-deep", wait: 2)
        XCTAssertFalse(deep.isEmpty, "a channel card should take focus")
        press(.menu)
        shot("grid-menu-on-filter", wait: 1.5)
        XCTAssertTrue(app.textFields.firstMatch.exists, "Menu should stay on the Live tab")
        XCTAssertNotEqual(focusedLabel, deep, "focus should leave the grid")
        press(.down)
        Thread.sleep(forTimeInterval: 1.5)
        shot("grid-back-down")
        XCTAssertEqual(focusedLabel, deep, "down from the controls should restore the card")
    }

    /// Plays a channel found by search (`STRMR_LIVE_CHANNEL`, default "A&E"), opens the
    /// Subtitles menu and turns on the first track. Plays video, so it only runs when
    /// /tmp/strmr-live-play exists.
    func testLivePlayerCaptionsMenu() throws {
        try XCTSkipUnless(FileManager.default.fileExists(atPath: "/tmp/strmr-live-play"),
                          "touch /tmp/strmr-live-play to run")
        app.launchArguments += ["-StrmrAutoSignIn", "1", "-live.mode", "channels"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Continue Watching"].waitForExistence(timeout: 40))
        Thread.sleep(forTimeInterval: 2)
        try app.focusTab("Live")
        Thread.sleep(forTimeInterval: 5)
        press(.down)
        let field = app.textFields.firstMatch
        for _ in 0..<6 where !field.hasFocus { press(.right, gap: 0.4) }
        XCTAssertTrue(field.hasFocus, "the search field")
        press(.select)
        Thread.sleep(forTimeInterval: 1.5)
        field.typeText(ProcessInfo.processInfo.environment["STRMR_LIVE_CHANNEL"] ?? "A&E")
        press(.menu)
        Thread.sleep(forTimeInterval: 4)
        press(.down)
        shot("player-search", wait: 1)
        press(.select)
        shot("player-tuning", wait: 12)
        press(.select)
        shot("player-chrome", wait: 1.5)
        press(.up)
        shot("player-buttons", wait: 1)
        press(.select)
        shot("player-subtitle-menu", wait: 1.5)
        press(.down)
        press(.select)
        shot("player-captions-on", wait: 6)
        shot("player-captions-on-2", wait: 4)
        press(.menu)
        press(.menu)
        shot("player-closed", wait: 2)
    }

    /// Swipe down during live playback (chrome hidden), then Menu: the player has to close.
    /// Plays video, so it only runs when /tmp/strmr-live-play exists.
    func testLivePlayerSwipeDownThenMenu() throws {
        try XCTSkipUnless(FileManager.default.fileExists(atPath: "/tmp/strmr-live-play"),
                          "touch /tmp/strmr-live-play to run")
        app.launchArguments += ["-StrmrAutoSignIn", "1", "-live.mode", "channels"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Continue Watching"].waitForExistence(timeout: 40))
        Thread.sleep(forTimeInterval: 2)
        try app.focusTab("Live")
        Thread.sleep(forTimeInterval: 5)
        press(.down)
        let field = app.textFields.firstMatch
        for _ in 0..<6 where !field.hasFocus { press(.right, gap: 0.4) }
        XCTAssertTrue(field.hasFocus, "the search field")
        press(.select)
        Thread.sleep(forTimeInterval: 1.5)
        field.typeText(ProcessInfo.processInfo.environment["STRMR_LIVE_CHANNEL"] ?? "A&E")
        press(.menu)
        Thread.sleep(forTimeInterval: 4)
        press(.down)
        press(.select)
        shot("swipe-tuning", wait: 12)
        press(.down)
        shot("swipe-down", wait: 1.5)
        if let dir = ProcessInfo.processInfo.environment["STRMR_SHOT_DIR"] {
            try? app.debugDescription.write(toFile: dir + "/swipe-down-tree.txt", atomically: true, encoding: .utf8)
        }
        press(.menu)
        shot("swipe-menu-1", wait: 2)
        press(.menu)
        shot("swipe-menu-2", wait: 2)
        XCTAssertTrue(app.textFields.firstMatch.waitForExistence(timeout: 5), "Menu should close the player")
    }
}
