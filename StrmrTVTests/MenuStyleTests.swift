import XCTest
@testable import StrmrTV

/// Settings › Menu › Menu Style: device-local, Default is the top bar.
@MainActor
final class MenuStyleTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "MenuStyleTests"

    override func setUp() {
        super.setUp()
        UserDefaults().removePersistentDomain(forName: suite)
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        UserDefaults().removePersistentDomain(forName: suite)
        super.tearDown()
    }

    func testDefaultIsTopBar() {
        let store = MenuStyleStore(defaults: defaults)
        XCTAssertNil(store.choice)
        XCTAssertEqual(store.style, .top)
    }

    func testSideMenuIsSavedOnThisDevice() {
        MenuStyleStore(defaults: defaults).choice = .side
        XCTAssertEqual(MenuStyleStore(defaults: defaults).style, .side)
    }

    func testDefaultRemovesTheSavedChoice() {
        let store = MenuStyleStore(defaults: defaults)
        store.choice = .side
        store.choice = nil
        XCTAssertNil(defaults.object(forKey: "menu.style"))
        XCTAssertEqual(MenuStyleStore(defaults: defaults).style, .top)
    }
}
