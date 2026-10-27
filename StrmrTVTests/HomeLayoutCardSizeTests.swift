import XCTest
@testable import StrmrTV

/// Card sizes for one kind of Home row: Default follows Card Size, a chosen size sizes
/// that kind alone, and the choices are kept on the device.
@MainActor
final class HomeLayoutCardSizeTests: XCTestCase {
    private var suite: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suite = "HomeLayoutCardSizeTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    func testUnsetStylesFollowCardSize() {
        let store = HomeLayoutStore(defaults: defaults)
        store.cardSize = .medium
        for style in ShelfStyle.allCases {
            XCTAssertEqual(store.cardScale(for: style), CardSize.medium.scale)
        }
    }

    func testStyleSizeAppliesToThatStyleAlone() {
        let store = HomeLayoutStore(defaults: defaults)
        store.cardSize = .medium
        store.styleCardSizes[.landscape] = .small
        XCTAssertEqual(store.cardScale(for: .landscape), CardSize.small.scale)
        XCTAssertEqual(store.cardScale(for: .poster), CardSize.medium.scale)
        XCTAssertEqual(store.cardScale(for: .expandingPoster), CardSize.medium.scale)
    }

    func testStyleSizesAreKept() {
        let store = HomeLayoutStore(defaults: defaults)
        store.styleCardSizes[.poster] = .extraLarge
        store.styleCardSizes[.expandingPoster] = .small
        store.styleCardSizes[.expandingPoster] = nil
        let reloaded = HomeLayoutStore(defaults: defaults)
        XCTAssertEqual(reloaded.styleCardSizes, [.poster: .extraLarge])
    }
}
