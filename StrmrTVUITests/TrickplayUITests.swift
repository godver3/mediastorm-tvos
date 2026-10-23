import XCTest

/// Stream-start loading art (cancel with Menu, then hand-off to the player) and the
/// software route's scrub thumbnails, on Coco. Resumes Coco, so its watch progress moves
/// by the ~30 s played; the scrub presses net to zero.
@MainActor
final class TrickplayUITests: XCTestCase {
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
            .write(to: URL(fileURLWithPath: dir).appendingPathComponent(String(format: "t%02d-%@.png", step, name)))
    }

    private var focusedLabel: String {
        let focused = app.descendants(matching: .any).element(matching: NSPredicate(format: "hasFocus == true"))
        return focused.exists ? focused.label : ""
    }

    private func press(_ button: XCUIRemote.Button, _ times: Int = 1, gap: TimeInterval = 0.2) {
        for _ in 0..<times {
            remote.press(button)
            Thread.sleep(forTimeInterval: gap)
        }
    }

    /// Opens Coco's details through Search so the pick never depends on row order.
    private func openCoco() throws {
        XCTAssertTrue(app.staticTexts["Continue Watching"].waitForExistence(timeout: 20))
        Thread.sleep(forTimeInterval: 2)
        try app.openFromSearch("coco", title: "Coco")
        XCTAssertTrue(focusedLabel.hasPrefix("Resume from"), "focused: \(focusedLabel)")
    }

    /// The loading art cross-fades between backdrops; Menu cancels before the (delayed)
    /// resolve runs, so nothing plays and no progress moves.
    func testLoadingArtRotation() throws {
        app.launchArguments += ["-StrmrAutoSignIn", "1", "-StrmrResolveDelay", "15"]
        app.launch()
        try openCoco()
        remote.press(.select)
        shot("rotation-a", wait: 1.5)
        shot("rotation-b", wait: 5)
        XCTAssertTrue(app.descendants(matching: .any)["PlaybackLoading"].exists)
        remote.press(.menu)
        shot("rotation-cancelled", wait: 2)
        XCTAssertTrue(focusedLabel.hasPrefix("Resume from"), "focused after cancel: \(focusedLabel)")
    }

    func testLoadingArtAndScrubPreview() throws {
        app.launchArguments += ["-StrmrAutoSignIn", "1", "-StrmrResolveDelay", "4"]
        app.launch()
        try openCoco()

        // Loading art, then Menu cancels back to details with Resume still focused.
        remote.press(.select)
        shot("loading", wait: 1.5)
        XCTAssertTrue(app.descendants(matching: .any)["PlaybackLoading"].exists)
        remote.press(.menu)
        shot("cancelled", wait: 2)
        XCTAssertTrue(focusedLabel.hasPrefix("Resume from"), "focused after cancel: \(focusedLabel)")

        // Play for real: art hands over to the player.
        remote.press(.select)
        shot("loading-again", wait: 2)
        shot("handoff", wait: 2.3)
        shot("player", wait: 12)

        // Scrub with right presses once thumbnails have had time to arrive.
        shot("before-scrub", wait: 12)
        press(.right, 3)
        shot("scrub-preview", wait: 0.3)
        press(.right)
        shot("scrub-preview-more", wait: 0.6)
        shot("scrub-committed", wait: 2.5)
        press(.left, 4)
        shot("scrub-back", wait: 0.4)
        Thread.sleep(forTimeInterval: 3)
        remote.press(.menu)
        shot("closed", wait: 3)
    }
}
