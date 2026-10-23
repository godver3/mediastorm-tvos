import XCTest

/// Home Layout settings on Home: moves along and between rows with a layout set by
/// launch arguments (UserDefaults keys `homeLayout.*`, from `STRMR_LAYOUT_ARGS`, e.g.
/// "-homeLayout.focusPosition center"), one screenshot per step, and checks every move
/// lands on a new card. Then opens Settings › Home Layout. Read-only.
@MainActor
final class HomeLayoutUITests: XCTestCase {
    override func setUp() async throws {
        continueAfterFailure = true
    }

    private let app = XCUIApplication()
    private let remote = XCUIRemote.shared

    private var prefix: String { ProcessInfo.processInfo.environment["STRMR_SHOT_PREFIX"] ?? "layout" }

    private func shot(_ name: String) {
        let dir = ProcessInfo.processInfo.environment["STRMR_SHOT_DIR"] ?? NSTemporaryDirectory()
        try? XCUIScreen.main.screenshot().pngRepresentation
            .write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(prefix)-\(name).png"))
    }

    private var focusedLabel: String {
        let focused = app.descendants(matching: .any).element(matching: NSPredicate(format: "hasFocus == true"))
        return focused.exists ? focused.label : ""
    }

    private func launch() {
        app.launchArguments += ["-StrmrAutoSignIn", "1"]
        let extra = ProcessInfo.processInfo.environment["STRMR_LAYOUT_ARGS"] ?? ""
        app.launchArguments += extra.split(separator: " ").map(String.init)
        app.launch()
        Thread.sleep(forTimeInterval: 12)
    }

    func testMoveAlongRows() {
        launch()
        remote.press(.down)
        Thread.sleep(forTimeInterval: 2)
        shot("r0c0")
        var labels = [focusedLabel]
        for step in 1...4 {
            remote.press(.right)
            Thread.sleep(forTimeInterval: 1.2)
            shot("r0c\(step)")
            labels.append(focusedLabel)
        }
        XCTAssertEqual(Set(labels).count, labels.count, "Every Right should land on a new card: \(labels)")
        for row in 1...3 {
            remote.press(.down)
            Thread.sleep(forTimeInterval: 1.5)
            shot("r\(row)")
            labels.append(focusedLabel)
            remote.press(.right)
            Thread.sleep(forTimeInterval: 1.2)
            shot("r\(row)c1")
        }
        // Back up to the first row: focus returns to the card left there.
        for _ in 1...3 { remote.press(.up); Thread.sleep(forTimeInterval: 1) }
        Thread.sleep(forTimeInterval: 1)
        XCTAssertEqual(focusedLabel, labels[4], "Up should return to the card left in the first row")
        shot("back")
        print("HOME_LAYOUT_FOCUS", labels.joined(separator: " | "))
    }

    /// Quick presses along the first row (the focus engine scrolls ahead of the app),
    /// then back: the focused card must end where the setting puts it.
    func testFastMoves() {
        launch()
        remote.press(.down)
        Thread.sleep(forTimeInterval: 2)
        let first = focusedLabel
        for _ in 0..<7 { remote.press(.right); Thread.sleep(forTimeInterval: 0.15) }
        Thread.sleep(forTimeInterval: 1.5)
        shot("fast-right")
        XCTAssertNotEqual(focusedLabel, first)
        for _ in 0..<4 { remote.press(.left); Thread.sleep(forTimeInterval: 0.15) }
        Thread.sleep(forTimeInterval: 1.5)
        shot("fast-left")
    }

    private func openHomeLayoutSettings() {
        remote.press(.up)
        Thread.sleep(forTimeInterval: 1)
        for _ in 0..<8 {
            if app.tabBars.buttons["Settings"].hasFocus { break }
            remote.press(.right)
            Thread.sleep(forTimeInterval: 0.6)
        }
        remote.press(.down)
        Thread.sleep(forTimeInterval: 1)
        for _ in 0..<12 {
            if focusedLabel.contains("Home Layout") { break }
            remote.press(.down)
            Thread.sleep(forTimeInterval: 0.6)
        }
        XCTAssertTrue(focusedLabel.contains("Home Layout"), "No Home Layout row, focus on \(focusedLabel)")
        remote.press(.select)
        Thread.sleep(forTimeInterval: 2)
    }

    private func moveDown(to label: String, limit: Int = 30) -> Bool {
        for _ in 0..<limit {
            if focusedLabel.hasPrefix(label) { return true }
            remote.press(.down)
            Thread.sleep(forTimeInterval: 0.5)
        }
        return focusedLabel.hasPrefix(label)
    }

    func testSettingsPage() {
        launch()
        openHomeLayoutSettings()
        shot("settings")
        for step in 1...14 {
            remote.press(.down)
            Thread.sleep(forTimeInterval: 0.6)
            if step % 4 == 0 { shot("settings-\(step)") }
        }
    }

    /// Sets the first row (`STRMR_ROW`, default Top 10 Today) to Landscape, shows Home,
    /// then resets every row to its default.
    func testChangeRowStyle() {
        let row = ProcessInfo.processInfo.environment["STRMR_ROW"] ?? "Top 10 Today"
        launch()
        openHomeLayoutSettings()
        XCTAssertTrue(moveDown(to: row), "No \(row) row, focus on \(focusedLabel)")
        remote.press(.select)
        Thread.sleep(forTimeInterval: 1.5)
        shot("style-options")
        XCTAssertTrue(moveDown(to: "Landscape", limit: 5), "No Landscape option, focus on \(focusedLabel)")
        remote.press(.select)
        Thread.sleep(forTimeInterval: 1.5)
        shot("style-set")
        remote.press(.menu)
        Thread.sleep(forTimeInterval: 1)
        remote.press(.menu)
        Thread.sleep(forTimeInterval: 1)
        for _ in 0..<8 {
            if app.tabBars.buttons["Home"].hasFocus { break }
            remote.press(.left)
            Thread.sleep(forTimeInterval: 0.5)
        }
        Thread.sleep(forTimeInterval: 2)
        remote.press(.down)
        Thread.sleep(forTimeInterval: 2)
        shot("style-home")

        openHomeLayoutSettings()
        XCTAssertTrue(moveDown(to: "Reset All Rows"), "No reset button")
        remote.press(.select)
        Thread.sleep(forTimeInterval: 1)
    }
}
