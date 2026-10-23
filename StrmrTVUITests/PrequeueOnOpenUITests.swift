import XCTest

/// Opening a title starts its prequeue as the push begins, and Play adopts it. The backend
/// side is checked in its log (one `[prequeue] Received request` per title, logged as the
/// details page opens rather than when Play is pressed). Plays a few seconds of one movie.
@MainActor
final class PrequeueOnOpenUITests: XCTestCase {
    override func setUp() async throws {
        continueAfterFailure = false
    }

    private let app = XCUIApplication()
    private let remote = XCUIRemote.shared
    private var step = 0

    private func shot(_ name: String) {
        step += 1
        let dir = ProcessInfo.processInfo.environment["STRMR_SHOT_DIR"] ?? NSTemporaryDirectory()
        try? XCUIScreen.main.screenshot().pngRepresentation
            .write(to: URL(fileURLWithPath: dir).appendingPathComponent(String(format: "p%02d-%@.png", step, name)))
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

    func testOpeningAMovieStartsItsPrequeue() {
        app.launchArguments += ["-StrmrAutoSignIn", "1"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Trending Movies"].waitForExistence(timeout: 40))
        Thread.sleep(forTimeInterval: 2)

        // Continue Watching, Watchlist, then Trending Movies; a few cards in.
        press(.down, 3)
        press(.right, 4)
        print("PREQUEUE-TEST opening: \(focusedLabel) at \(Date().timeIntervalSince1970)")
        press(.select)
        let primary = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Play' OR label BEGINSWITH 'Resume'")).firstMatch
        XCTAssertTrue(primary.waitForExistence(timeout: 20), "details should open")
        shot("details")

        // Give the prequeue opened with the page time to resolve, then play.
        Thread.sleep(forTimeInterval: 20)
        print("PREQUEUE-TEST play: \(focusedLabel) at \(Date().timeIntervalSince1970)")
        press(.select, gap: 0)
        Thread.sleep(forTimeInterval: 3)
        shot("after-play-3s")
        Thread.sleep(forTimeInterval: 5)
        shot("after-play-8s")
        press(.menu)
        Thread.sleep(forTimeInterval: 2)
        press(.menu)
        Thread.sleep(forTimeInterval: 2)
        shot("back")
    }
}
