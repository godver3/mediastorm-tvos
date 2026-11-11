import XCTest

/// Not a test: the iPhone / iPad counterpart of the tvOS remote driver. Serves HTTP on
/// 127.0.0.1:$STRMR_DRIVER_PORT (default 7791) so the simulator can be driven one call at a
/// time: taps, swipes, rotation, screenshots and element queries. Skipped unless the runner
/// gets STRMR_DRIVER=1. Start it with `scripts/ios start`; endpoints are in `scripts/ios help`.
@MainActor
final class MobileDriverUITests: XCTestCase {
    private let app = XCUIApplication(bundleIdentifier: "com.strmr.app.nx")
    private var serving = true
    private var issues: [String] = []

    override func record(_ issue: XCTIssue) {
        issues.append(issue.compactDescription)
    }

    func testServe() throws {
        let env = ProcessInfo.processInfo.environment
        try XCTSkipUnless(env["STRMR_DRIVER"] == "1", "mobile driver: run through scripts/ios start")
        continueAfterFailure = true
        let port = UInt16(env["STRMR_DRIVER_PORT"] ?? "") ?? 7791
        let server = try DriverServer(port: port)
        server.start()
        defer { server.stop() }
        if app.state == .notRunning { app.launch() } else { app.activate() }
        print("[MobileDriver] listening on \(port)")
        while serving {
            if let request = server.next() {
                issues = []
                let response = handle(request)
                request.respond(issues.isEmpty ? response : .text(issues.joined(separator: "\n"), status: 500))
            } else {
                RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.02))
            }
        }
    }

    private func handle(_ request: DriverServer.Request) -> DriverServer.Response {
        let q = request.query
        switch request.path {
        case "/ping":
            return .text("ok")
        case "/launch":
            app.terminate()
            app.launchArguments = (q["args"] ?? "").split(separator: " ").map(String.init)
            app.launch()
            return .json(["state": app.state.rawValue])
        case "/activate":
            app.activate()
            return .json(["state": app.state.rawValue])
        case "/terminate":
            app.terminate()
            return .text("ok")
        case "/shot":
            return DriverServer.Response(contentType: "image/png", body: XCUIScreen.main.screenshot().pngRepresentation)
        case "/tap":
            return tap(q, long: false)
        case "/longpress":
            return tap(q, long: true)
        case "/swipe":
            return swipe(q)
        case "/scrollto":
            return scrollTo(q["q"] ?? "", max: Int(q["max"] ?? "") ?? 12, direction: q["dir"] ?? "up")
        case "/back":
            let back = app.navigationBars.buttons.element(boundBy: 0)
            guard back.exists else { return .text("no navigation back button", status: 404) }
            back.tap()
            return .text("ok")
        case "/rotate":
            let orientation: UIDeviceOrientation = switch q["o"] ?? "portrait" {
            case "landscape", "landscapeleft": .landscapeLeft
            case "landscaperight": .landscapeRight
            default: .portrait
            }
            XCUIDevice.shared.orientation = orientation
            Thread.sleep(forTimeInterval: 0.8)
            return .text("ok")
        case "/tree":
            return .text(app.debugDescription)
        case "/find":
            return find(q["q"] ?? "", limit: Int(q["limit"] ?? "") ?? 25)
        case "/wait":
            let target = q["q"] ?? ""
            let element = match(target)
            let found = element.waitForExistence(timeout: TimeInterval(q["timeout"] ?? "") ?? 20)
            return found ? .json(describe(element)) : .text("not found: \(target)", status: 404)
        case "/type":
            if let target = q["q"], !target.isEmpty { match(target).tap() }
            app.typeText(q["text"] ?? "")
            return .text("ok")
        case "/quit":
            serving = false
            return .text("bye")
        default:
            return .text("unknown endpoint \(request.path)", status: 404)
        }
    }

    /// The first element labelled or identified `text` exactly, else one containing it.
    private func match(_ text: String) -> XCUIElement {
        let exact = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@ OR identifier == %@", text, text)).firstMatch
        if exact.exists { return exact }
        return app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS[c] %@ OR identifier CONTAINS[c] %@", text, text)).firstMatch
    }

    /// `q=TEXT` (exact label / identifier first, then contains; `i=N` picks the Nth match), or
    /// `x=&y=` in points from the top left of the screen.
    private func tap(_ q: [String: String], long: Bool) -> DriverServer.Response {
        if let x = Double(q["x"] ?? ""), let y = Double(q["y"] ?? "") {
            let target = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: x, dy: y))
            if long { target.press(forDuration: 1.0) } else { target.tap() }
        } else {
            let text = q["q"] ?? ""
            var element = match(text)
            if let i = Int(q["i"] ?? "") {
                element = app.descendants(matching: .any)
                    .matching(NSPredicate(format: "label CONTAINS[c] %@ OR identifier CONTAINS[c] %@", text, text))
                    .element(boundBy: i)
            }
            guard element.waitForExistence(timeout: 5) else { return .text("not found: \(text)", status: 404) }
            // The element's own tap, not a computed coordinate: building a touch from a coordinate
            // inside a landscape-only player on a portrait device asserted in XCTest and ended the
            // driver (and with it the app).
            if long { element.press(forDuration: 1.0) } else { element.tap() }
        }
        Thread.sleep(forTimeInterval: 0.4)
        return .text("ok")
    }

    /// `dir=up|down|left|right` (finger direction) on `q=TEXT`, else the whole app.
    private func swipe(_ q: [String: String]) -> DriverServer.Response {
        let element = (q["q"]).map(match) ?? app
        guard element.exists else { return .text("not found: \(q["q"] ?? "")", status: 404) }
        let n = max(1, Int(q["n"] ?? "") ?? 1)
        for _ in 0..<n {
            switch q["dir"] ?? "up" {
            case "down": element.swipeDown()
            case "left": element.swipeLeft()
            case "right": element.swipeRight()
            default: element.swipeUp()
            }
        }
        Thread.sleep(forTimeInterval: 0.4)
        return .text("ok")
    }

    /// Swipes the page until an element labelled `text` is on screen and hittable.
    private func scrollTo(_ text: String, max: Int, direction: String) -> DriverServer.Response {
        for _ in 0...max {
            let element = match(text)
            if element.exists, element.isHittable { return .json(describe(element)) }
            direction == "down" ? app.swipeDown() : app.swipeUp()
        }
        return .text("not found after \(max) swipes: \(text)", status: 404)
    }

    private func find(_ text: String, limit: Int) -> DriverServer.Response {
        let matches = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS[c] %@ OR identifier CONTAINS[c] %@", text, text))
        let count = matches.count
        let items = (0..<min(count, limit)).map { describe(matches.element(boundBy: $0)) }
        return .json(["count": count, "items": items])
    }

    private func describe(_ element: XCUIElement) -> [String: Any] {
        let f = element.frame
        return [
            "label": element.label,
            "identifier": element.identifier,
            "type": "\(element.elementType.rawValue)",
            "hittable": element.isHittable,
            "frame": [Int(f.minX), Int(f.minY), Int(f.width), Int(f.height)],
            "value": (element.value as? String) ?? "",
        ]
    }
}
