import XCTest

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
