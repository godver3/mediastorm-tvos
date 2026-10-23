import XCTest

/// Top Shelf links: `details` opens the title's details page over Home; `play` opens it
/// and starts the primary action. Set `STRMR_DEEPLINK_PLAY=1` to also exercise play
/// (it starts a real stream).
@MainActor
final class TopShelfDeepLinkUITests: XCTestCase {
    private let app = XCUIApplication()

    override func setUp() async throws {
        continueAfterFailure = false
    }

    private func shot(_ name: String) {
        let dir = ProcessInfo.processInfo.environment["STRMR_SHOT_DIR"] ?? NSTemporaryDirectory()
        try? XCUIScreen.main.screenshot().pngRepresentation
            .write(to: URL(fileURLWithPath: dir).appendingPathComponent("topshelf-\(name).png"))
    }

    private func open(_ action: String) {
        let url = URL(string: "com.strmr.app.nx://\(action)?titleId=tmdb:movie:603&name=The%20Matrix&mediaType=movie&year=1999&tmdb=603&imdb=tt0133093")!
        app.open(url)
        // The system may ask "Open in Strmr?" for a link from outside the app.
        Thread.sleep(forTimeInterval: 2)
        if XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["Open"].exists
            || !app.wait(for: .runningForeground, timeout: 1) {
            XCUIRemote.shared.press(.select)
        }
    }

    func testDetailsLinkOpensDetails() {
        app.launchArguments += ["-StrmrAutoSignIn", "1"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["Home"].firstMatch.waitForExistence(timeout: 40))
        Thread.sleep(forTimeInterval: 5)
        open("details")
        // Details: its primary action and the title (logo label or name text).
        XCTAssertTrue(app.buttons["Play"].waitForExistence(timeout: 20)
            || app.descendants(matching: .any)["The Matrix"].firstMatch.waitForExistence(timeout: 5))
        shot("details")
        if ProcessInfo.processInfo.environment["STRMR_DEEPLINK_PLAY"] == "1" {
            XCUIRemote.shared.press(.menu)
            open("play")
            Thread.sleep(forTimeInterval: 8)
            shot("play")
        }
    }
}
