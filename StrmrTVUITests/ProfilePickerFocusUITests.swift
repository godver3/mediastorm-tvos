import XCTest

/// The picker's "Use this profile automatically" tickbox: Down reaches it from a profile
/// that isn't above it, and Up returns to that profile. Needs a stored session with
/// several profiles and no auto-select profile, so launch lands on the picker.
@MainActor
final class ProfilePickerFocusUITests: XCTestCase {
    private let app = XCUIApplication()
    private let remote = XCUIRemote.shared
    private let checkbox = "Use this profile automatically"

    override func setUp() async throws {
        continueAfterFailure = false
    }

    private var focusedLabel: String {
        let focused = app.descendants(matching: .any).element(matching: NSPredicate(format: "hasFocus == true"))
        return focused.exists ? focused.label : ""
    }

    private func press(_ button: XCUIRemote.Button) -> String {
        remote.press(button)
        Thread.sleep(forTimeInterval: 0.8)
        return focusedLabel
    }

    func testCheckboxFocusFromEdgeProfile() {
        app.launch()
        Thread.sleep(forTimeInterval: 8)
        XCTAssertTrue(app.staticTexts["Who's Watching?"].exists, "Expected the profile picker at launch")

        // The last profile, away from the centred tickbox.
        var edge = focusedLabel
        for _ in 0..<10 {
            let next = press(.right)
            if next == edge { break }
            edge = next
        }
        XCTAssertNotEqual(edge, checkbox)

        XCTAssertEqual(press(.down), checkbox, "Down from \(edge) should reach the tickbox")
        XCTAssertEqual(press(.up), edge, "Up should return to \(edge)")
    }

    /// Every profile, with the box toggled in between, Up lands where Down left.
    func testCheckboxReturnsToEachProfile() {
        app.launch()
        Thread.sleep(forTimeInterval: 8)
        for _ in 0..<10 { _ = press(.left) }
        var results: [String] = []
        var current = focusedLabel
        for index in 0..<10 {
            let down = press(.down)
            if index % 2 == 1 { remote.press(.select); Thread.sleep(forTimeInterval: 0.8) }
            let up = press(.up)
            results.append("\(current)→\(down)→\(up)")
            let next = press(.right)
            if next == current { break }
            current = next
        }
        print("PICKER_FOCUS", results.joined(separator: " | "))
        XCTAssertTrue(results.allSatisfy {
            let parts = $0.components(separatedBy: "→")
            return parts[1] == checkbox && parts[0] == parts[2]
        }, results.joined(separator: " | "))
    }
}
