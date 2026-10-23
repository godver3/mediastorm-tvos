import XCTest

/// Reaching a top-menu tab by name. The profile (and Settings > Menu) choose which tabs
/// show, so a tab's place in the bar is not fixed: never reach one by counting presses.
@MainActor
extension XCUIApplication {
    /// Moves focus up into the tab bar and along it to the tab labelled `name`, which also
    /// selects it. Skips the test when this profile's menu hides the tab.
    func focusTab(_ name: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let remote = XCUIRemote.shared
        let tab = tabBars.buttons[name]
        let inTabBar = tabBars.buttons.matching(NSPredicate(format: "hasFocus == true"))
        for _ in 0..<6 where inTabBar.count == 0 {
            remote.press(.up)
            Thread.sleep(forTimeInterval: 0.6)
        }
        guard tab.waitForExistence(timeout: 5) else {
            throw XCTSkip("The \(name) tab is hidden in this profile's menu")
        }
        // Right to the end, then left across the whole bar.
        for direction in [XCUIRemote.Button.right, .left] {
            for _ in 0..<8 where !tab.hasFocus {
                remote.press(direction)
                Thread.sleep(forTimeInterval: 0.6)
            }
            if tab.hasFocus { return }
        }
        XCTFail("Couldn't focus the \(name) tab", file: file, line: line)
    }

    /// Opens a title's details through Search, so the pick never depends on row order:
    /// types `query`, then moves along the results to the card labelled `title`.
    func openFromSearch(_ query: String, title: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let remote = XCUIRemote.shared
        try focusTab("Search", file: file, line: line)
        XCTAssertTrue(searchFields.firstMatch.waitForExistence(timeout: 5), "the Search tab", file: file, line: line)
        remote.press(.down)
        typeText(query)
        Thread.sleep(forTimeInterval: 4)
        remote.press(.down)
        Thread.sleep(forTimeInterval: 0.6)
        for _ in 0..<6 {
            remote.press(.left)
            Thread.sleep(forTimeInterval: 0.4)
        }
        for _ in 0..<8 where focusedLabel != title {
            remote.press(.right)
            Thread.sleep(forTimeInterval: 0.6)
        }
        XCTAssertEqual(focusedLabel, title, file: file, line: line)
        remote.press(.select)
        Thread.sleep(forTimeInterval: 4)
    }

    private var focusedLabel: String {
        let focused = descendants(matching: .any).element(matching: NSPredicate(format: "hasFocus == true"))
        return focused.exists ? focused.label : ""
    }
}
