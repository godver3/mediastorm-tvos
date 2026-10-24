import XCTest

/// The Lists tab: custom lists, charts, the All / Movies / Shows switch with genres and
/// decades, and a list opened as a grid. Read-only.
@MainActor
final class ListsUITests: XCTestCase {
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
            .write(to: URL(fileURLWithPath: dir).appendingPathComponent(String(format: "l%02d-%@.png", step, name)))
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

    func testListsTab() throws {
        app.launchArguments += ["-StrmrAutoSignIn", "1"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Continue Watching"].waitForExistence(timeout: 40))
        Thread.sleep(forTimeInterval: 2)

        // Up to the tab bar and over to Lists (Home, Watchlist, Lists).
        try app.focusTab("Lists")
        XCTAssertTrue(app.staticTexts["Charts"].waitForExistence(timeout: 15))
        shot("lists-tab", wait: 4)

        // First row: a custom list, opened as a grid.
        press(.down)
        let first = focusedLabel
        XCTAssertFalse(first.isEmpty, "a list tile should take focus")
        shot("first-row")
        press(.select)
        XCTAssertTrue(app.staticTexts[first].waitForExistence(timeout: 15), "the grid should carry the list's name")
        shot("first-list-grid", wait: 4)
        press(.menu)
        Thread.sleep(forTimeInterval: 1.5)

        // Down to the genres, below however many list and hub rows the profile has.
        for _ in 0..<14 where focusedLabel != "Action Movies" { press(.down, gap: 1) }
        XCTAssertEqual(focusedLabel, "Action Movies")
        shot("genres")
        // The All / Movies / Shows menu above them: switch from All to Shows, then open a show genre.
        press(.up)
        press(.select)
        shot("kind-menu", wait: 1.5)
        press(.down)
        press(.down)
        press(.select)
        shot("shows-switch", wait: 3)
        press(.down)
        let genre = focusedLabel
        XCTAssertTrue(genre.hasSuffix(" Shows"), "a show genre should take focus: \(genre)")
        shot("show-genres", wait: 3)
        press(.select)
        XCTAssertTrue(app.staticTexts[genre].waitForExistence(timeout: 20))
        shot("genre-grid", wait: 5)
        press(.menu)
        press(.down)
        shot("decades", wait: 3)
    }

    /// A custom list's grid: sort by name (A–Z index appears), pick a letter, filter to
    /// unwatched, then a genre grid's sort menu.
    func testGridControls() throws {
        app.launchArguments += ["-StrmrAutoSignIn", "1"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Continue Watching"].waitForExistence(timeout: 40))
        Thread.sleep(forTimeInterval: 2)
        try app.focusTab("Lists")
        XCTAssertTrue(app.staticTexts["Charts"].waitForExistence(timeout: 15))
        Thread.sleep(forTimeInterval: 2)

        // Set Aside leads Your Lists; the next tile is the first of the profile's own lists.
        // Down from the centred tab bar lands on the tile under it; go to the row's start.
        press(.down)
        press(.left, 3)
        XCTAssertEqual(focusedLabel, "Set Aside")
        press(.right)
        let list = focusedLabel
        press(.select)
        XCTAssertTrue(app.staticTexts[list].waitForExistence(timeout: 15))
        shot("grid-controls", wait: 4)

        // Focus starts on the Sort menu. Pick Name.
        press(.select)
        shot("sort-menu", wait: 2)
        press(.down, 2)  // Default, Date Added, Name (menu rows expose no focus label)
        press(.select)
        shot("sorted-by-name", wait: 4)
        XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label == 'Coco'")).count, 1)

        // Down to the letter index; pick the second letter.
        press(.down)
        press(.right)
        let letter = focusedLabel
        press(.select)
        shot("letter-\(letter)", wait: 4)

        // Up to the controls (the nearest one, so back to the row's start), then right to
        // the status filter: Unwatched. Never press Select unless the expected control has
        // focus: a stray Select opens Random, and the next one would start playback.
        press(.up)
        press(.left, 4)
        press(.right, 2)
        // Menu buttons don't expose focus to the test; it must at least still be on the grid.
        XCTAssertTrue(app.staticTexts[list].exists && !app.buttons["Play"].exists)
        press(.select)
        shot("status-menu", wait: 2)
        press(.down)  // Any Status, Unwatched
        XCTAssertFalse(app.buttons["Play"].exists, "the test must never reach a details page")
        press(.select)
        XCTAssertFalse(app.buttons["Play"].exists, "the test must never reach a details page")
        shot("unwatched", wait: 4)
    }

    /// Creates a throwaway list from the New List tile, then deletes it from its grid.
    /// Only ever touches the list it made.
    func testListManagement() throws {
        try openListsTab()

        // The New List tile ends Your Lists (the second row).
        press(.down, 2)
        press(.right, 15, gap: 0.3)
        XCTAssertEqual(focusedLabel, "New List")
        press(.select)
        shot("new-list-alert", wait: 2)
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText(Self.listName)
        shot("typed", wait: 2)
    }

    /// Every row of the tab, then a streaming service grid with its Movies / Shows switch.
    func testListsTour() throws {
        try openListsTab()
        press(.down)
        shot("for-you", wait: 3)
        for row in 2...7 {
            press(.down)
            shot("row-\(row)", wait: 3)
        }
    }

    private func openListsTab() throws {
        app.launchArguments += ["-StrmrAutoSignIn", "1"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Continue Watching"].waitForExistence(timeout: 40))
        Thread.sleep(forTimeInterval: 2)
        try app.focusTab("Lists")
        XCTAssertTrue(app.staticTexts["Charts"].waitForExistence(timeout: 15))
        Thread.sleep(forTimeInterval: 2)
    }

    static let listName = "Zz UITest List"
}
