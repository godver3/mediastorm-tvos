import XCTest
@testable import StrmrTV

/// Home's Top Carousel and Focused Title Info choices: their defaults, the
/// migration from the first pass's single Home Style, and Card Size's Extra Large.
@MainActor
final class HomeStyleStoreTests: XCTestCase {
    private var suite: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suite = "HomeStyleStoreTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    func testDefaultsAreClassic() {
        let store = HomeStyleStore(defaults: defaults)
        XCTAssertFalse(store.topCarousel)
        XCTAssertTrue(store.focusedInfo)
        XCTAssertTrue(store.isClassic)
        XCTAssertNil(store.carouselRow)
    }

    func testLegacyCarouselMigratesToCarouselWithoutInfo() {
        defaults.set("carousel", forKey: HomeStyleStore.Keys.legacyStyle)
        defaults.set("trending-tv", forKey: HomeStyleStore.Keys.carouselRow)
        let store = HomeStyleStore(defaults: defaults)
        XCTAssertTrue(store.topCarousel)
        XCTAssertFalse(store.focusedInfo)
        XCTAssertFalse(store.isClassic)
        XCTAssertEqual(store.carouselRow, "trending-tv")
        XCTAssertNil(defaults.object(forKey: HomeStyleStore.Keys.legacyStyle))
    }

    func testLegacyClassicMigratesToDefaults() {
        defaults.set("classic", forKey: HomeStyleStore.Keys.legacyStyle)
        let store = HomeStyleStore(defaults: defaults)
        XCTAssertTrue(store.isClassic)
        XCTAssertNil(defaults.object(forKey: HomeStyleStore.Keys.legacyStyle))
        XCTAssertNil(defaults.object(forKey: HomeStyleStore.Keys.topCarousel))
        XCTAssertNil(defaults.object(forKey: HomeStyleStore.Keys.focusedInfo))
    }

    func testChoicesPersistIndependently() {
        let store = HomeStyleStore(defaults: defaults)
        store.topCarousel = true
        store.focusedInfo = false
        store.carouselRow = "my-list"
        let reloaded = HomeStyleStore(defaults: defaults)
        XCTAssertTrue(reloaded.topCarousel)
        XCTAssertFalse(reloaded.focusedInfo)
        XCTAssertEqual(reloaded.carouselRow, "my-list")

        reloaded.topCarousel = false
        XCTAssertFalse(HomeStyleStore(defaults: defaults).topCarousel)
        XCTAssertFalse(HomeStyleStore(defaults: defaults).focusedInfo)
    }

    func testExtraLargeCards() {
        XCTAssertEqual(CardSize.allCases, [.small, .medium, .large, .extraLarge])
        XCTAssertEqual((ShelfRow.baseCardHeight * CardSize.extraLarge.scale).rounded(), 338)
        // The profile's scale (0.5–1) never names Extra Large.
        XCTAssertEqual(CardSize(nearest: 1), .large)
    }
}
