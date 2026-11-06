import XCTest

/// Opens the stock transport bar and its menus on Apple's sample stream.
@MainActor
final class ChromeProbeUITests: XCTestCase {
    func testNativeChrome() {
        let app = XCUIApplication()
        app.launchArguments += ["-StrmrChromeProbe", "1", "-StrmrProbeHideNative",
                                ProcessInfo.processInfo.environment["STRMR_HIDE_NATIVE"] ?? "0"]
        app.launchEnvironment["STRMR_SHOT_DIR"] = ProcessInfo.processInfo.environment["STRMR_SHOT_DIR"]
        app.launch()
        let dir = ProcessInfo.processInfo.environment["STRMR_SHOT_DIR"] ?? NSTemporaryDirectory()
        var n = 0
        func shot(_ name: String, _ wait: TimeInterval = 2) {
            Thread.sleep(forTimeInterval: wait); n += 1
            try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir + String(format: "/probe-%02d-%@.png", n, name)))
        }
        let remote = XCUIRemote.shared
        shot("playing", 8)
        remote.press(.select)
        shot("paused-bar")
        remote.press(.up)
        shot("up-1")
        try? app.debugDescription.write(toFile: dir + "/ax-up.txt", atomically: true, encoding: .utf8)
        try? app.debugDescription.write(toFile: dir + "/ax-up.txt", atomically: true, encoding: .utf8)
        remote.press(.select)
        shot("focused-menu-open", 2)
        remote.press(.menu)
        for k in 0..<3 {
            remote.press(.right)
            shot("right-\(k)", 1)
        }
        remote.press(.select)
        shot("rightmost-open", 2)
    }
}

/// Opens the custom Audio menu on the probe player and picks the last track.
@MainActor
final class ChromeProbeAudioMenuUITests: XCTestCase {
    func testAudioMenuSelection() {
        let app = XCUIApplication()
        app.launchArguments += ["-StrmrChromeProbe", "1", "-StrmrProbeHideNative", "1"]
        app.launchEnvironment["STRMR_SHOT_DIR"] = ProcessInfo.processInfo.environment["STRMR_SHOT_DIR"]
        app.launch()
        let dir = ProcessInfo.processInfo.environment["STRMR_SHOT_DIR"] ?? NSTemporaryDirectory()
        var n = 0
        func shot(_ name: String, _ wait: TimeInterval = 1.5) {
            Thread.sleep(forTimeInterval: wait); n += 1
            try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir + String(format: "/audio-%02d-%@.png", n, name)))
        }
        let remote = XCUIRemote.shared
        shot("playing", 8)
        remote.press(.select)
        shot("bar")
        remote.press(.up)
        shot("up")
        remote.press(.select)
        shot("menu-open")
        remote.press(.down); Thread.sleep(forTimeInterval: 0.4)
        remote.press(.down); Thread.sleep(forTimeInterval: 0.4)
        shot("menu-down")
        remote.press(.select)
        shot("picked", 2)
    }
}
