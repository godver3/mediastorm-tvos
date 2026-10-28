import XCTest
@testable import StrmrTV

/// Animate Expansion: on until chosen, kept on the device, and offered while any row
/// draws expanding posters.
@MainActor
final class HomeLayoutAnimateExpansionTests: XCTestCase {
    private var suite: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suite = "HomeLayoutAnimateExpansionTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    func testOnByDefault() {
        XCTAssertTrue(HomeLayoutStore(defaults: defaults).animateExpansion)
    }

    func testChoiceIsKept() {
        HomeLayoutStore(defaults: defaults).animateExpansion = false
        XCTAssertFalse(HomeLayoutStore(defaults: defaults).animateExpansion)
    }

    func testOfferedWhileAnyRowExpands() {
        let store = HomeLayoutStore(defaults: defaults)
        XCTAssertTrue(store.usesExpandingPosters)
        store.expandPosters = false
        XCTAssertFalse(store.usesExpandingPosters)
        store.setStyle(.expandingPoster, for: "trending-movies")
        XCTAssertTrue(store.usesExpandingPosters)
    }
}
