import XCTest

/// Walks Home's server-configured rows top to bottom, one screenshot per row, and
/// checks each Down lands on a new card. Read-only: it never changes the profile.
@MainActor
final class HomeShelvesUITests: XCTestCase {
    override func setUp() async throws {
        continueAfterFailure = true
    }

    private let app = XCUIApplication()
    private let remote = XCUIRemote.shared

    private func shot(_ name: String) {
        let dir = ProcessInfo.processInfo.environment["STRMR_SHOT_DIR"] ?? NSTemporaryDirectory()
        try? XCUIScreen.main.screenshot().pngRepresentation
            .write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }

    private var focusedLabel: String {
        let focused = app.descendants(matching: .any).element(matching: NSPredicate(format: "hasFocus == true"))
        return focused.exists ? focused.label : ""
    }

    func testWalkConfiguredRows() {
        app.launchArguments += ["-StrmrAutoSignIn", "1"]
        app.launch()
        Thread.sleep(forTimeInterval: 15)

        var seen: [String] = []
        for row in 0..<30 {
            remote.press(.down)
            Thread.sleep(forTimeInterval: 2.5)
            let label = focusedLabel
            shot(String(format: "row%02d", row))
            if label == seen.last { break }  // the last row: Down has nowhere to go
            seen.append(label)
        }
        print("HOME_ROWS", seen.joined(separator: " | "))
        XCTAssertGreaterThan(seen.count, 4, "Expected the configured rows, got \(seen)")
    }

    /// Watch Something's Search card switches to the Search tab; Surprise Me opens a
    /// title's details over Home. Needs the profile's config to have Watch Something.
    func testWatchSomethingActions() {
        app.launchArguments += ["-StrmrAutoSignIn", "1"]
        app.launch()
        Thread.sleep(forTimeInterval: 10)

        var found = false
        for _ in 0..<12 {
            remote.press(.down)
            Thread.sleep(forTimeInterval: 1.5)
            if focusedLabel == "Search" { found = true; break }
        }
        XCTAssertTrue(found, "No Watch Something row")

        remote.press(.right)
        Thread.sleep(forTimeInterval: 1)
        if focusedLabel == "Surprise Me" {
            remote.press(.select)
            Thread.sleep(forTimeInterval: 20)
            shot("surprise-details")
            remote.press(.menu)
            Thread.sleep(forTimeInterval: 2)
            XCTAssertEqual(focusedLabel, "Surprise Me", "Back should return to the card")
        }

        remote.press(.left)
        Thread.sleep(forTimeInterval: 1)
        remote.press(.select)
        Thread.sleep(forTimeInterval: 3)
        shot("search-tab")
        XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: 5), "Search card should open the Search tab")
    }
}
