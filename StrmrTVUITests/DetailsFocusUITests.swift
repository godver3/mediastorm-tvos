import XCTest

/// Up / Down between details rows is steered, not geometric: the action row always enters on
/// Play, the season chips and episodes enter on the current one and then on whichever was
/// last focused there. Read-only: it only moves focus.
@MainActor
final class DetailsFocusUITests: XCTestCase {
    override func setUp() async throws {
        continueAfterFailure = false
    }

    private let app = XCUIApplication()
    private let remote = XCUIRemote.shared

    private var focusedLabel: String {
        let focused = app.descendants(matching: .any).element(matching: NSPredicate(format: "hasFocus == true"))
        return focused.exists ? focused.label : ""
    }

    private func press(_ button: XCUIRemote.Button, _ times: Int = 1, gap: TimeInterval = 0.8) {
        for _ in 0..<times {
            remote.press(button)
            Thread.sleep(forTimeInterval: gap)
        }
    }

    private func isPrimary(_ label: String) -> Bool {
        label.hasPrefix("Play") || label.hasPrefix("Resume")
    }

    private func isChip(_ label: String) -> Bool {
        label.hasPrefix("Season") || label == "Specials"
    }

    func testRowsEnterOnFirstOrRemembered() throws {
        app.launchArguments += ["-StrmrAutoSignIn", "1"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Continue Watching"].waitForExistence(timeout: 40))
        Thread.sleep(forTimeInterval: 2)
        // A long-running series, through Search so the pick never depends on Home's rows.
        try app.openFromSearch("breaking bad", title: "Breaking Bad")
        XCTAssertTrue(app.buttons["Watch State"].waitForExistence(timeout: 20), "series details should open")
        Thread.sleep(forTimeInterval: 3)
        XCTAssertTrue(isPrimary(focusedLabel), "details should open on Play: \(focusedLabel)")

        // Start from the far end of the action row: Down still enters the next row on its
        // current item, not the nearest one.
        press(.right, 5)
        press(.down)
        let hasChips = isChip(focusedLabel)
        let chip = focusedLabel
        if hasChips { press(.down) }
        let firstEpisode = focusedLabel
        XCTAssertTrue(firstEpisode.hasPrefix("Episode"), "focused: \(firstEpisode)")

        // Move along the episodes, then back up: the action row re-enters on Play.
        press(.right, 2)
        let movedEpisode = focusedLabel
        XCTAssertNotEqual(movedEpisode, firstEpisode)
        if hasChips {
            press(.up)
            XCTAssertEqual(focusedLabel, chip, "chips should re-enter on the current season")
        }
        press(.up)
        XCTAssertTrue(isPrimary(focusedLabel), "actions should re-enter on Play: \(focusedLabel)")

        // Back down from another action: the episode row returns to the one last focused.
        press(.right)
        press(.down, hasChips ? 2 : 1)
        XCTAssertEqual(focusedLabel, movedEpisode, "episodes should return to the last focused")

        guard hasChips else { return }
        // A chip focused (not selected) elsewhere in the row is remembered too.
        press(.up)
        press(.right)
        let movedChip = focusedLabel
        if movedChip != chip, isChip(movedChip) {
            press(.down)
            XCTAssertEqual(focusedLabel, movedEpisode)
            press(.up)
            XCTAssertEqual(focusedLabel, movedChip, "chips should return to the last focused")
        }
    }

    /// The episode row first enters on the episode Play targets (up next), not episode 1.
    func testEpisodesEnterOnUpNext() throws {
        app.launchArguments += ["-StrmrAutoSignIn", "1"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Continue Watching"].waitForExistence(timeout: 40))
        Thread.sleep(forTimeInterval: 2)
        press(.down)
        press(.select)
        Thread.sleep(forTimeInterval: 6)
        guard app.buttons["Watch State"].exists else {
            throw XCTSkip("the first Continue Watching item is a movie")
        }
        let primary = focusedLabel
        guard let range = primary.range(of: #"S\d{2}E(\d{2,})"#, options: .regularExpression) else {
            throw XCTSkip("no episode code on Play: \(primary)")
        }
        let episode = Int(primary[range].split(separator: "E").last ?? "") ?? 0
        press(.down)
        if isChip(focusedLabel) { press(.down) }
        XCTAssertTrue(focusedLabel.hasPrefix("Episode \(episode),"),
                      "expected episode \(episode) (\(primary)), focused: \(focusedLabel)")
    }
}
