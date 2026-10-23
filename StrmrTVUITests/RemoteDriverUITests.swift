import XCTest

/// Not a test: a long-running remote driver for agents and scripts. Serves HTTP on
/// 127.0.0.1:$STRMR_DRIVER_PORT (default 7790) so the simulator can be driven one call at a
/// time, without a rebuild per step. Skipped unless the runner gets STRMR_DRIVER=1, so a
/// normal test run never blocks here. Start it with `scripts/tv start`; endpoints are listed
/// in `scripts/tv help`.
@MainActor
final class RemoteDriverUITests: XCTestCase {
    private let app = XCUIApplication()
    private let remote = XCUIRemote.shared
    private var serving = true
    /// Failures recorded while handling a request (an element that isn't there, a press
    /// that can't be synthesized): answered as errors instead of ending the driver.
    private var issues: [String] = []

    override func record(_ issue: XCTIssue) {
        issues.append(issue.compactDescription)
    }

    func testServe() throws {
        let env = ProcessInfo.processInfo.environment
        try XCTSkipUnless(env["STRMR_DRIVER"] == "1", "remote driver: run through scripts/tv start")
        continueAfterFailure = true
        let port = UInt16(env["STRMR_DRIVER_PORT"] ?? "") ?? 7790
        let server = try DriverServer(port: port)
        server.start()
        defer { server.stop() }
        // Attach to the app if it is already running (scripts/run-sim.sh), else launch it.
        if app.state == .notRunning { app.launch() } else { app.activate() }
        print("[RemoteDriver] listening on \(port)")
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
        case "/press":
            return press(q)
        case "/shot":
            let png = XCUIScreen.main.screenshot().pngRepresentation
            return DriverServer.Response(contentType: "image/png", body: png)
        case "/focus":
            return .json(focused())
        case "/tree":
            return .text(app.debugDescription)
        case "/find":
            return find(q["q"] ?? "", limit: Int(q["limit"] ?? "") ?? 25)
        case "/wait":
            let target = q["q"] ?? ""
            let timeout = TimeInterval(q["timeout"] ?? "") ?? 20
            let element = app.descendants(matching: .any)
                .matching(NSPredicate(format: "label == %@ OR identifier == %@", target, target)).firstMatch
            let found = element.waitForExistence(timeout: timeout)
            return found ? .json(describe(element)) : .text("not found: \(target)", status: 404)
        case "/type":
            app.typeText(q["text"] ?? "")
            return .json(focused())
        case "/quit":
            serving = false
            return .text("bye")
        default:
            return .text("unknown endpoint \(request.path)", status: 404)
        }
    }

    /// `seq=down,down,select` (or `b=down&n=2`), `gap` seconds between presses, `hold`
    /// seconds for a long press. Answers with the focused element once focus settles.
    private func press(_ q: [String: String]) -> DriverServer.Response {
        let names = q["seq"].map { $0.split(separator: ",").map(String.init) }
            ?? Array(repeating: q["b"] ?? "", count: max(1, Int(q["n"] ?? "") ?? 1))
        let gap = TimeInterval(q["gap"] ?? "") ?? 0.35
        let hold = TimeInterval(q["hold"] ?? "") ?? 0
        var buttons: [XCUIRemote.Button] = []
        for name in names {
            guard let button = Self.buttons[name.lowercased()] else {
                return .text("unknown button \(name); use \(Self.buttons.keys.sorted().joined(separator: ", "))", status: 400)
            }
            buttons.append(button)
        }
        for button in buttons {
            if hold > 0 { remote.press(button, forDuration: hold) } else { remote.press(button) }
            Thread.sleep(forTimeInterval: gap)
        }
        return .json(focused())
    }

    private static let buttons: [String: XCUIRemote.Button] = [
        "up": .up, "down": .down, "left": .left, "right": .right, "select": .select,
        "menu": .menu, "back": .menu, "play": .playPause, "playpause": .playPause, "home": .home,
    ]

    private func focused() -> [String: Any] {
        let element = app.descendants(matching: .any).element(matching: NSPredicate(format: "hasFocus == true"))
        return element.exists ? describe(element) : ["focused": NSNull()]
    }

    /// Elements whose label or identifier contains `text` (case-insensitive).
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
            "type": Self.typeNames[element.elementType] ?? "\(element.elementType.rawValue)",
            "focused": element.hasFocus,
            "frame": [Int(f.minX), Int(f.minY), Int(f.width), Int(f.height)],
            "value": (element.value as? String) ?? "",
        ]
    }

    private static let typeNames: [XCUIElement.ElementType: String] = [
        .other: "other", .button: "button", .cell: "cell", .staticText: "text", .image: "image",
        .textField: "textField", .searchField: "searchField", .tabBar: "tabBar", .scrollView: "scrollView",
        .collectionView: "collectionView", .switch: "switch", .slider: "slider", .window: "window",
    ]
}
